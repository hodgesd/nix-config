#!/usr/bin/env python3
"""hn-summaries: one Hacker News discussion summary per story, shared by every Mac.

Serves two read-only endpoints on the tailnet (hn-summaries.nix binds the port;
the firewall in hosts/common/nixos-common.nix keeps it off the LAN):

  GET /healthz                   {"ok": true, "cached": N, "llm_calls_today": N, "daily_cap": N, ...}
  GET /hn?ids=1,2,3&llm=1        {"<id>": {"summary", "source", "model", "fetched_at"}, ...}
                                 missing ids are omitted; llm=0 never spends money

Pipeline per id: SQLite -> miss marker -> HN Companion (free) -> Algolia thread
text -> OpenRouter chat completion. The thread flattening, the prompt and the
"overview + '• Theme — sentence' bullets" contract are the plugin's own code
(daily_news_uv.2h.py in hodgesd/swiftbar_plugins), copied verbatim below so a
tooltip looks the same whichever side produced it.

Spend controls (settings come from the environment, set in hn-summaries.nix):
single-flight per id, HN_LLM_CONCURRENCY paid calls in flight, HN_DAILY_LLM_CAP
paid calls per UTC day, HN_LLM_TIMEOUT per call, HN_THREAD_CHAR_BUDGET of input.
Every paid call logs one "llm id=..." line with tokens and cost: the journal is
the ledger.
"""
import asyncio
import datetime
import json
import logging
import os
import re
import sqlite3
import time
from typing import Optional

import aiohttp
from aiohttp import ClientTimeout, web
from bs4 import BeautifulSoup

log = logging.getLogger("hn-summaries")

# ── Settings (hn-summaries.nix is the source of truth; these are the fallbacks) ──
PORT = int(os.environ.get("HN_PORT", "8090"))
MODEL = os.environ.get("HN_MODEL", "openai/gpt-5-mini")
REASONING_EFFORT = os.environ.get("HN_REASONING_EFFORT", "minimal")  # "" sends no reasoning field
MAX_TOKENS = int(os.environ.get("HN_MAX_TOKENS", "4096"))
DAILY_LLM_CAP = int(os.environ.get("HN_DAILY_LLM_CAP", "60"))
LLM_TIMEOUT = float(os.environ.get("HN_LLM_TIMEOUT", "30"))
LLM_CONCURRENCY = int(os.environ.get("HN_LLM_CONCURRENCY", "3"))
THREAD_CHAR_BUDGET = int(os.environ.get("HN_THREAD_CHAR_BUDGET", "80000"))
MISS_TTL_HOURS = float(os.environ.get("HN_MISS_TTL_HOURS", "6"))
MIN_COMMENTS = int(os.environ.get("HN_MIN_COMMENTS", "3"))  # fewer is not a discussion worth a paid call
MAX_IDS_PER_REQUEST = 50  # the front page is 15; a topic batch is a handful
# The secret. Empty means the paid path is off (cache + Companion keep working).
OPENROUTER_API_KEY = os.environ.get("OPENROUTER_API_KEY", "").strip()
# systemd's StateDirectory; "." only when run by hand for a test
DB_PATH = os.path.join(os.environ.get("STATE_DIRECTORY", "."), "hn-summaries.db")

# Overridable so a test can point Companion at a dead port and exercise the paid path.
HNCOMPANION_API = os.environ.get("HN_COMPANION_API", "https://app.hncompanion.com/api/posts/")
ALGOLIA_ITEM_URL = "https://hn.algolia.com/api/v1/items/"
OPENROUTER_CHAT_URL = "https://openrouter.ai/api/v1/chat/completions"
REQUEST_TIMEOUT = 10  # Algolia / Companion, seconds


# ── Ported verbatim from daily_news_uv.2h.py (hodgesd/swiftbar_plugins) ───────────
# Keep these identical to the plugin: docs/HN-SUMMARIES.md has the check command.
HN_COMMENT_MAX_CHARS = 600


HN_STORY_TEXT_MAX_CHARS = 1500


SUMMARY_INSTRUCTION = (
    "Summarize the Hacker News discussion above for a short tooltip. Output exactly this, as "
    "plain text: one overview paragraph of 2-3 sentences; a blank line; then 3-5 bullet lines, "
    "each formatted \"• Theme — one sentence\" (a 2-5 word theme, an em dash, one sentence). "
    "Cover the key insights and the main disagreements. No headers, no bold, no markdown, no "
    "preamble, nothing after the bullets."
)


HN_URL = "https://news.ycombinator.com/"


def cap_tooltip(text: str, max_chars: int) -> str:
    """Truncate tooltip text at a word boundary with an ellipsis if it exceeds max_chars."""
    if len(text) <= max_chars:
        return text
    return text[:max_chars].rsplit(' ', 1)[0] + '…'


def _comment_text(node: dict) -> str:
    """Plain text of one Algolia node; '' for deleted, dead or empty comments."""
    html = node.get('text')
    if not html or not node.get('author'):
        return ''
    text = re.sub(r'\s+', ' ', BeautifulSoup(html, 'html.parser').get_text(' ', strip=True)).strip()
    if not text or re.fullmatch(r'\[(deleted|dead|flagged|removed)\]', text, re.I):
        return ''
    return text


def count_comments(item: dict) -> int:
    return sum(1 + count_comments(child) for child in item.get('children') or [])


def flatten_hn_thread(item: dict, char_budget: int) -> str:
    """Render an Algolia item tree as indented "author: text" lines under a title header.

    Depth-first order is kept, but the budget is handed out breadth-first: every top-level
    comment first, then their direct replies, then deeper tails while room remains, and a
    reply is only kept when its parent was. A busy thread therefore loses its deep
    sub-arguments before it loses a single top-level take.
    """
    url = item.get('url') or f"{HN_URL}item?id={item.get('id')}"
    header = f"Title: {item.get('title') or 'Untitled'}\nURL: {url}\n"
    story_text = _comment_text(item)
    if story_text:
        header += f"Post: {cap_tooltip(story_text, HN_STORY_TEXT_MAX_CHARS)}\n"
    header += "\nComments:\n"

    nodes = []  # (depth, parent index, rendered line) in depth-first order

    def walk(children, depth, parent):
        for child in children or []:
            text = _comment_text(child)
            if text:
                index = len(nodes)
                indent = '  ' * depth
                nodes.append((depth, parent, f"{indent}{child.get('author')}: "
                                             f"{cap_tooltip(text, HN_COMMENT_MAX_CHARS)}\n"))
                walk(child.get('children'), depth + 1, index)
            else:
                # A deleted comment's replies still belong to the thread: attach them one level up
                walk(child.get('children'), depth, parent)

    walk(item.get('children'), 0, None)

    kept = set()
    used = len(header)
    for wanted in (0, 1, None):  # passes: top-level, first replies, then everything deeper
        for index, (depth, parent, line) in enumerate(nodes):
            if index in kept or (depth != wanted if wanted is not None else depth < 2):
                continue
            if parent is not None and parent not in kept:
                continue
            if used + len(line) > char_budget:
                continue
            kept.add(index)
            used += len(line)

    return header + ''.join(line for index, (_, _, line) in enumerate(nodes) if index in kept)


def sanitize_llm_summary(text: str) -> str:
    """Coerce a model reply into the overview + "• Theme — sentence" bullets the tooltip expects.

    Strips code fences, bold and headers; normalises "-", "*" and numbered bullets to "• ";
    folds wrapped bullet continuations back onto their bullet. '' when nothing usable is left.
    """
    text = (text or '').replace('\r', '')
    text = re.sub(r'^\s*```[\w-]*\s*$', '', text, flags=re.M)
    text = text.replace('**', '')
    overview, bullets = [], []
    for raw in text.split('\n'):
        line = re.sub(r'\s+', ' ', raw).strip()
        line = re.sub(r'^#+\s*', '', line)
        line = re.sub(r'^(overview|summary)\s*:\s*', '', line, flags=re.I)
        if not line:
            continue
        bullet = re.match(r'^(?:[-*•·▪◦]|\d+[.)])\s*(.+)$', line)
        if bullet:
            body = bullet.group(1).strip()
            if ' — ' not in body:
                # "Theme: sentence" / "Theme - sentence" -> "Theme — sentence"
                body = re.sub(r'^(.{2,60}?)\s*(?::\s|\s-{1,2}\s|\s–\s)\s*', r'\1 — ', body, count=1)
            bullets.append(f'• {body}')
        elif not bullets:
            overview.append(line)
        else:
            bullets[-1] = f'{bullets[-1]} {line}'
    parts = [' '.join(overview).strip(), '\n'.join(bullets)]
    condensed = '\n\n'.join(part for part in parts if part)
    if len(condensed) > 1200:
        condensed = condensed[:1200].rsplit(' ', 1)[0] + '…'
    return condensed


def condense_hncompanion_summary(md: str) -> str:
    """Condense HN Companion's structured markdown summary into tooltip-sized plain text."""
    def strip_md(text: str) -> str:
        text = re.sub(r'\[([^\]]*)\]\([^)]*\)', r'\1', text)  # [text](url) -> text
        text = text.replace('**', '').replace('`', '')
        return re.sub(r'\s+', ' ', text).strip()

    # Split the markdown into sections keyed by heading
    sections = {}
    current = None
    for line in md.splitlines():
        heading = re.match(r'#+\s+(.+)', line)
        if heading:
            current = heading.group(1).strip().lower()
            sections[current] = []
        elif current is not None:
            sections[current].append(line)

    overview = strip_md(' '.join(sections.get('overview', [])))

    # Themes appear as "*   **Theme Name:** description" (same line) or with the
    # description indented on following lines — handle both
    theme_lines = []
    themes_raw = '\n'.join(sections.get('main themes & key insights', []))
    for match in re.finditer(
        r'^\s*[*-]\s+\*\*(.+?)\*\*:?\s*(.*?)(?=^\s*[*-]\s+\*\*|\Z)',
        themes_raw, re.M | re.S,
    ):
        name = strip_md(match.group(1)).rstrip(':')
        desc = strip_md(match.group(2))
        first_sentence = re.split(r'(?<=[.!?])\s', desc)[0] if desc else ''
        theme_lines.append(f'• {name} — {first_sentence}' if first_sentence else f'• {name}')

    parts = [p for p in (overview, '\n'.join(theme_lines)) if p]
    condensed = '\n\n'.join(parts) if parts else strip_md(md)

    if len(condensed) > 1200:
        condensed = condensed[:1200].rsplit(' ', 1)[0] + '…'
    return condensed
# ── End of the ported block ────────────────────────────────────────────────────


# ── Storage ───────────────────────────────────────────────────────────────────
SCHEMA = """
CREATE TABLE IF NOT EXISTS summaries (
    id TEXT PRIMARY KEY, summary TEXT NOT NULL, source TEXT NOT NULL,
    model TEXT, fetched_at INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS misses (id TEXT PRIMARY KEY, expires_at INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS llm_calls (
    ts INTEGER NOT NULL, id TEXT NOT NULL, model TEXT, ok INTEGER NOT NULL,
    prompt_tokens INTEGER, completion_tokens INTEGER, reasoning_tokens INTEGER, cost_usd REAL);
CREATE INDEX IF NOT EXISTS llm_calls_ts ON llm_calls (ts);
"""


class Store:
    """SQLite under StateDirectory. Queries are tiny, so they run inline on the loop."""

    def __init__(self, path: str):
        self.db = sqlite3.connect(path, check_same_thread=False, isolation_level=None)
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.executescript(SCHEMA)

    def get(self, story_id: str) -> Optional[dict]:
        row = self.db.execute(
            "SELECT summary, source, model, fetched_at FROM summaries WHERE id = ?", (story_id,)
        ).fetchone()
        if not row:
            return None
        return {"summary": row[0], "source": row[1], "model": row[2], "fetched_at": row[3]}

    def put(self, story_id: str, summary: str, source: str, model: Optional[str]) -> dict:
        now = int(time.time())
        self.db.execute(
            "INSERT OR REPLACE INTO summaries (id, summary, source, model, fetched_at) VALUES (?, ?, ?, ?, ?)",
            (story_id, summary, source, model, now),
        )
        self.db.execute("DELETE FROM misses WHERE id = ?", (story_id,))
        return {"summary": summary, "source": source, "model": model, "fetched_at": now}

    def has_fresh_miss(self, story_id: str) -> bool:
        row = self.db.execute("SELECT expires_at FROM misses WHERE id = ?", (story_id,)).fetchone()
        return bool(row) and row[0] > time.time()

    def mark_miss(self, story_id: str) -> None:
        """The paid path failed for this story; do not retry it until the TTL passes."""
        self.db.execute(
            "INSERT OR REPLACE INTO misses (id, expires_at) VALUES (?, ?)",
            (story_id, int(time.time() + MISS_TTL_HOURS * 3600)),
        )

    def llm_calls_today(self) -> int:
        midnight = datetime.datetime.now(datetime.timezone.utc).replace(
            hour=0, minute=0, second=0, microsecond=0)
        return self.db.execute(
            "SELECT count(*) FROM llm_calls WHERE ts >= ?", (int(midnight.timestamp()),)
        ).fetchone()[0]

    def record_llm_call(self, story_id: str, ok: bool, usage: dict) -> None:
        self.db.execute(
            "INSERT INTO llm_calls (ts, id, model, ok, prompt_tokens, completion_tokens, reasoning_tokens, cost_usd)"
            " VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (int(time.time()), story_id, MODEL, int(ok), usage.get("prompt_tokens"),
             usage.get("completion_tokens"), usage.get("reasoning_tokens"), usage.get("cost")),
        )

    def cached(self) -> int:
        return self.db.execute("SELECT count(*) FROM summaries").fetchone()[0]


# ── Sources ───────────────────────────────────────────────────────────────────
async def fetch_hncompanion_summary(session: aiohttp.ClientSession, story_id: str) -> Optional[str]:
    """HN Companion's free cached summary, condensed like the plugin does; None on a miss."""
    try:
        async with session.get(f"{HNCOMPANION_API}{story_id}") as response:
            if response.status != 200:
                return None  # 404 = not in their cache; expected
            data = await response.json()
            summary = data.get("summary")
            return condense_hncompanion_summary(summary) if summary else None
    except Exception:
        return None


async def fetch_hn_thread(session: aiohttp.ClientSession, story_id: str) -> Optional[dict]:
    """The story and its full comment tree from Algolia's items endpoint; None on any failure."""
    try:
        async with session.get(f"{ALGOLIA_ITEM_URL}{story_id}") as response:
            if response.status != 200:
                return None
            return await response.json()
    except Exception:
        return None


class LlmUnavailable(Exception):
    """The API refused us for a reason no story can fix: auth, credits, rate limit."""


async def openrouter_summary(session: aiohttp.ClientSession, document: str) -> tuple:
    """One chat completion over HTTPS. Returns (reply_text, usage). Raises on failure."""
    payload = {
        "model": MODEL,
        # Same shape as `cat thread | llm "<instruction>"`: the document first, the ask last.
        "messages": [{"role": "user", "content": f"{document}\n\n{SUMMARY_INSTRUCTION}"}],
        "max_tokens": MAX_TOKENS,  # caps runaway output and OpenRouter's per-call credit hold
        "usage": {"include": True},  # ask for the cost so the journal line can carry it
    }
    if REASONING_EFFORT:
        payload["reasoning"] = {"effort": REASONING_EFFORT}
    headers = {
        "Authorization": f"Bearer {OPENROUTER_API_KEY}",
        "Content-Type": "application/json",
        # OpenRouter attribution headers; harmless and shows up in their dashboard
        "HTTP-Referer": "https://github.com/hodgesd/nix-config",
        "X-Title": "hn-summaries",
    }
    async with session.post(OPENROUTER_CHAT_URL, json=payload, headers=headers,
                            timeout=ClientTimeout(total=LLM_TIMEOUT)) as response:
        body = await response.text()
        if response.status in (401, 402, 403, 429):
            raise LlmUnavailable(f"HTTP {response.status}: {' '.join(body.split())[:300]}")
        if response.status != 200:
            raise RuntimeError(f"HTTP {response.status}: {' '.join(body.split())[:300]}")
    data = json.loads(body)
    if "error" in data:  # OpenRouter can answer 200 with an error object for provider failures
        raise RuntimeError(str(data["error"])[:300])
    text = (data.get("choices") or [{}])[0].get("message", {}).get("content") or ""
    usage = data.get("usage") or {}
    details = usage.get("completion_tokens_details") or {}
    return text, {
        "prompt_tokens": usage.get("prompt_tokens"),
        "completion_tokens": usage.get("completion_tokens"),
        "reasoning_tokens": details.get("reasoning_tokens"),
        "cost": usage.get("cost"),
    }


# ── Resolution ────────────────────────────────────────────────────────────────
class Service:
    def __init__(self, store: Store, session: aiohttp.ClientSession):
        self.store = store
        self.session = session
        self.locks: dict = {}  # story id -> (asyncio.Lock, waiters) for single-flight
        self.llm_slots = asyncio.Semaphore(LLM_CONCURRENCY)
        self.llm_disabled_until = 0.0  # after an auth/credit/rate-limit answer, back off
        self.llm_in_flight = 0  # reserved cap slots: calls started but not yet recorded
        self.cap_logged_day = None

    async def resolve(self, story_id: str, llm: bool) -> Optional[dict]:
        hit = self.store.get(story_id)
        if hit:
            return {**hit, "source": "cache"}
        # Single flight: three Macs asking for the same fresh story make one call.
        lock, waiters = self.locks.get(story_id) or (asyncio.Lock(), 0)
        self.locks[story_id] = (lock, waiters + 1)
        try:
            async with lock:
                hit = self.store.get(story_id)
                if hit:
                    return {**hit, "source": "cache"}
                return await self._produce(story_id, llm)
        finally:
            lock, waiters = self.locks[story_id]
            if waiters <= 1:
                del self.locks[story_id]
            else:
                self.locks[story_id] = (lock, waiters - 1)

    async def _produce(self, story_id: str, llm: bool) -> Optional[dict]:
        condensed = await fetch_hncompanion_summary(self.session, story_id)
        if condensed:
            return self.store.put(story_id, condensed, "companion", None)
        if not llm:
            return None
        if not OPENROUTER_API_KEY or time.monotonic() < self.llm_disabled_until:
            return None
        if self.store.has_fresh_miss(story_id):
            return None
        # Count the calls in flight too, and reserve this one before the first
        # await: two stories resolving at once would otherwise both pass the
        # check before either is recorded.
        used = self.store.llm_calls_today() + self.llm_in_flight
        if used >= DAILY_LLM_CAP:
            today = datetime.date.today()
            if self.cap_logged_day != today:  # one line per day, not one per request
                self.cap_logged_day = today
                log.warning("daily cap reached (%d/%d paid calls); cache + Companion only until UTC midnight",
                            used, DAILY_LLM_CAP)
            return None
        self.llm_in_flight += 1
        try:
            item = await fetch_hn_thread(self.session, story_id)
            if not item:
                return None  # Algolia hiccup: free to retry on the next request
            if count_comments(item) < MIN_COMMENTS:
                return None
            document = flatten_hn_thread(item, THREAD_CHAR_BUDGET)

            started = time.monotonic()
            async with self.llm_slots:
                try:
                    text, usage = await openrouter_summary(self.session, document)
                except LlmUnavailable as exc:
                    # Not the story's fault, so no miss marker; but stop paying for a while
                    self.llm_disabled_until = time.monotonic() + 600
                    self.store.record_llm_call(story_id, False, {})
                    log.error("llm unavailable, paid path paused 10 min: %s", exc)
                    return None
                except Exception as exc:
                    self.store.record_llm_call(story_id, False, {})
                    self.store.mark_miss(story_id)
                    log.warning("llm id=%s failed after %.1fs: %s", story_id, time.monotonic() - started, exc)
                    return None
            self.store.record_llm_call(story_id, True, usage)
        finally:
            self.llm_in_flight -= 1
        log.info("llm id=%s model=%s prompt_tokens=%s completion_tokens=%s reasoning_tokens=%s cost_usd=%s "
                 "elapsed=%.1fs thread_chars=%d",
                 story_id, MODEL, usage.get("prompt_tokens"), usage.get("completion_tokens"),
                 usage.get("reasoning_tokens"), usage.get("cost"), time.monotonic() - started, len(document))
        summary = sanitize_llm_summary(text)
        if not summary:
            self.store.mark_miss(story_id)  # never store a failure as a summary
            log.warning("llm id=%s: nothing usable in the reply", story_id)
            return None
        return self.store.put(story_id, summary, "llm", MODEL)


# ── HTTP ──────────────────────────────────────────────────────────────────────
def parse_ids(raw: str) -> list:
    ids = [part.strip() for part in raw.split(",") if part.strip()]
    if not ids or len(ids) > MAX_IDS_PER_REQUEST or not all(part.isdigit() for part in ids):
        raise web.HTTPBadRequest(text=f"ids: 1-{MAX_IDS_PER_REQUEST} comma-separated numeric story ids\n")
    return list(dict.fromkeys(ids))


async def handle_hn(request: web.Request) -> web.Response:
    service: Service = request.app["service"]
    ids = parse_ids(request.query.get("ids", ""))
    llm = request.query.get("llm", "0").lower() in ("1", "true", "yes")
    started = time.monotonic()
    results = await asyncio.gather(*(service.resolve(story_id, llm) for story_id in ids))
    found = {story_id: result for story_id, result in zip(ids, results) if result}
    sources = {name: sum(1 for r in found.values() if r["source"] == name) for name in ("cache", "companion", "llm")}
    log.info("hn ids=%d llm=%d cache=%d companion=%d llm_new=%d missing=%d in %.1fs from %s",
             len(ids), llm, sources["cache"], sources["companion"], sources["llm"], len(ids) - len(found),
             time.monotonic() - started, request.remote)
    return web.json_response(found)


async def handle_healthz(request: web.Request) -> web.Response:
    service: Service = request.app["service"]
    return web.json_response({
        "ok": True,
        "cached": service.store.cached(),
        "llm_calls_today": service.store.llm_calls_today(),
        "daily_cap": DAILY_LLM_CAP,
        "llm_enabled": bool(OPENROUTER_API_KEY),
        "model": MODEL,
    })


async def make_app() -> web.Application:
    app = web.Application(client_max_size=1024)  # GET only; nothing to upload
    timeout = ClientTimeout(total=REQUEST_TIMEOUT)
    session = aiohttp.ClientSession(timeout=timeout)
    app["service"] = Service(Store(DB_PATH), session)
    app.router.add_get("/healthz", handle_healthz)
    app.router.add_get("/hn", handle_hn)

    async def close(app):
        await session.close()
    app.on_cleanup.append(close)
    return app


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")  # journald adds the time
    if not OPENROUTER_API_KEY:
        log.warning("OPENROUTER_API_KEY is empty; serving cache + HN Companion only")
    log.info("model=%s reasoning=%s daily_cap=%d timeout=%ss budget=%d chars db=%s",
             MODEL, REASONING_EFFORT or "off", DAILY_LLM_CAP, LLM_TIMEOUT, THREAD_CHAR_BUDGET, DB_PATH)
    # Dual-stack: asyncio sets IPV6_V6ONLY on "::", so both families are bound explicitly.
    web.run_app(make_app(), host=["0.0.0.0", "::"], port=PORT, access_log=None, print=None)


if __name__ == "__main__":
    main()
