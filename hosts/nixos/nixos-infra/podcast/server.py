"""Read-later podcast: intake API, job queue, TTS worker and RSS feed.

One process, two threads:

- intake (stdlib ThreadingHTTPServer): POST /enqueue takes {"url": …} or
  {"text": …, "title": …} with a bearer token, stores a job and answers
  202 at once. Text that is really a link is queued as the link, and text
  without a title is titled from its first line (speech.py). GET /healthz for Gatus.
- worker: one job at a time. Fetch → speech.extract_html / from_text →
  one Kokoro request per piece → ffmpeg concat → MP3 → feed.xml. A failed
  job keeps its reason in the jobs table and never reaches the feed.

State is one SQLite file (the jobs table is both queue and episode list)
plus public/, which holds feed.xml and the MP3s. public/ is the only part
of the state dir the ts-podcast sidecar serves through Funnel.

Settings come from the environment (podcast.nix); PODCAST_INTAKE_TOKEN and
PODCAST_FEED_TOKEN come from sops.
"""

from __future__ import annotations

import hmac
import ipaddress
import json
import os
import re
import shutil
import socket
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
import traceback
import urllib.error
import urllib.parse
import urllib.request
import uuid
import wave
import xml.etree.ElementTree as ET
from collections.abc import Iterator
from contextlib import contextmanager
from datetime import UTC, datetime
from email.utils import format_datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

import speech

STATE = Path(os.environ.get("PODCAST_STATE_DIR", "/var/lib/podcast"))
PUBLIC = STATE / "public"
DB = STATE / "podcast.db"
BIND = os.environ.get("PODCAST_BIND", "0.0.0.0")
PORT = int(os.environ.get("PODCAST_PORT", "8095"))
KOKORO = os.environ.get("KOKORO_URL", "http://127.0.0.1:8880").rstrip("/")
VOICE = os.environ.get("PODCAST_VOICE", "af_heart")
PUBLIC_BASE = os.environ["PODCAST_PUBLIC_BASE"].rstrip("/")
RETENTION_DAYS = int(os.environ.get("PODCAST_RETENTION_DAYS", "30"))
FEED_TITLE = os.environ.get("PODCAST_FEED_TITLE", "Read Later")
INTAKE_TOKEN = os.environ["PODCAST_INTAKE_TOKEN"]
FEED_TOKEN = os.environ["PODCAST_FEED_TOKEN"]
# Feed artwork (a PNG in the Nix store), copied into public/ at startup
# because ts-podcast only sees public/.
COVER = os.environ.get("PODCAST_COVER", "")

MAX_BODY = 2_000_000  # bytes of JSON one intake request may carry
MAX_PAGE = 10_000_000  # bytes of HTML one fetch may read
# Longest article synthesized: about 3 hours of audio, ~600 MB of WAV in
# tmp/ while it runs. A 2 MB paste could otherwise mean a day of audio.
MAX_WORDS = 30_000
SAMPLE_RATE = 24_000  # Kokoro's output; silence is written to match
USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
    "(KHTML, like Gecko) Version/18.0 Safari/605.1.15"
)
ITUNES = "http://www.itunes.com/dtds/podcast-1.0.dtd"
ATOM = "http://www.w3.org/2005/Atom"
# Characters XML 1.0 forbids; ElementTree writes them anyway, and one in a
# pasted title would make Overcast reject the whole feed.
XML_INVALID = re.compile("[^\t\n\r\x20-\ud7ff\ue000-\ufffd\U00010000-\U0010ffff]")

WAKE = threading.Event()


def log(msg: str) -> None:
    print(msg, flush=True)


def feed_base() -> str:
    """Public URL prefix of feed.xml and the MP3s (the token is the only lock)."""
    return f"{PUBLIC_BASE}/p/{FEED_TOKEN}"


# ── State ───────────────────────────────────────────────────────────────


@contextmanager
def db() -> Iterator[sqlite3.Connection]:
    conn = sqlite3.connect(DB, timeout=30, isolation_level=None)  # autocommit
    conn.row_factory = sqlite3.Row
    try:
        yield conn
    finally:
        conn.close()


def init_db() -> None:
    with db() as conn:
        conn.execute(
            """CREATE TABLE IF NOT EXISTS jobs (
                id TEXT PRIMARY KEY,       -- also the episode guid and MP3 name
                created REAL NOT NULL,
                url TEXT,                  -- set for URL jobs
                text TEXT,                 -- set for pasted-text jobs
                title TEXT,                -- as sent; extraction may supply one
                status TEXT NOT NULL,      -- queued | working | done | failed
                reason TEXT,               -- why it failed
                ep_title TEXT,
                ep_summary TEXT,           -- the spoken intro line
                published REAL,
                bytes INTEGER,
                duration REAL
            )"""
        )
        # A job cut off by a restart is simply run again.
        conn.execute("UPDATE jobs SET status = 'queued' WHERE status = 'working'")


def enqueue(url: str, text: str, title: str) -> str:
    job_id = uuid.uuid4().hex
    with db() as conn:
        conn.execute(
            "INSERT INTO jobs (id, created, url, text, title, status) "
            "VALUES (?, ?, ?, ?, ?, 'queued')",
            (job_id, time.time(), url or None, text or None, title or None),
        )
    WAKE.set()
    return job_id


def claim() -> sqlite3.Row | None:
    with db() as conn:
        row = conn.execute(
            "SELECT * FROM jobs WHERE status = 'queued' ORDER BY created LIMIT 1"
        ).fetchone()
        if row is not None:
            conn.execute("UPDATE jobs SET status = 'working' WHERE id = ?", (row["id"],))
        return row


# ── Intake ──────────────────────────────────────────────────────────────


def authorized(header: str) -> bool:
    # SECURITY: a request here becomes an outbound fetch and an episode in
    # an internet-reachable feed, so it needs a credential even though only
    # the tailnet can reach this port. Constant-time compare; the token is
    # never logged (log lines carry the job id and URL only).
    scheme, _, token = header.partition(" ")
    return scheme.lower() == "bearer" and hmac.compare_digest(
        token.strip().encode(), INTAKE_TOKEN.encode()
    )


class Intake(BaseHTTPRequestHandler):
    server_version = "read-later-podcast"

    def reply(self, code: int, body: dict[str, Any]) -> None:
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self) -> None:
        if self.path != "/healthz":
            self.reply(404, {"error": "not found"})
            return
        with db() as conn:
            rows = conn.execute("SELECT status, count(*) FROM jobs GROUP BY status")
            counts = {status: n for status, n in rows}
        kokoro = kokoro_ready(timeout=3)
        self.reply(200, {"ok": kokoro, "kokoro": kokoro, "jobs": counts})

    def do_POST(self) -> None:
        if self.path != "/enqueue":
            self.reply(404, {"error": "not found"})
            return
        if not authorized(self.headers.get("Authorization", "")):
            self.reply(401, {"error": "missing or wrong bearer token"})
            return
        length = int(self.headers.get("Content-Length") or 0)
        if not 0 < length <= MAX_BODY:
            self.reply(413 if length else 400, {"error": "body must be 1 byte to 2 MB of JSON"})
            return
        try:
            body = json.loads(self.rfile.read(length))
            url = str(body.get("url") or "").strip()
            text = str(body.get("text") or "").strip()
            title = str(body.get("title") or "").strip()
        except (ValueError, AttributeError):
            self.reply(400, {"error": "body must be a JSON object"})
            return
        # The Share Sheet Shortcut sends everything as text; a link (alone,
        # or with a headline as news apps share it) is fetched as the URL.
        if not url and (link := speech.link_capture(text)):
            url, text = link, ""
        if url and urllib.parse.urlsplit(url).scheme not in ("http", "https"):
            self.reply(400, {"error": "url must be http or https"})
            return
        if not url and not text:
            self.reply(400, {"error": "send {url} or {text, title}"})
            return
        job_id = enqueue(url, text, title)
        if url:
            log(f"queued id={job_id} url={url}")
        else:
            log(f"queued id={job_id} text_chars={len(text)} title={title!r}")
        self.reply(202, {"id": job_id, "status": "queued"})

    def log_message(self, format: str, *args: Any) -> None:
        pass  # one line per job from log() is enough; requests carry tokens in headers only


# ── Fetch ───────────────────────────────────────────────────────────────


def check_public(url: str) -> None:
    # SECURITY: whatever is fetched is read aloud into a feed that is
    # reachable from the internet. A URL that points into the homelab (LAN,
    # tailnet, loopback, link-local) would publish a private page, so only
    # globally routable addresses are fetched, re-checked on every redirect.
    # Residual: DNS rebinding between this lookup and the connect.
    parts = urllib.parse.urlsplit(url)
    if parts.scheme not in ("http", "https") or not parts.hostname:
        raise speech.ExtractionError("only http and https URLs can be fetched")
    port = parts.port or (443 if parts.scheme == "https" else 80)
    try:
        infos = socket.getaddrinfo(parts.hostname, port, proto=socket.IPPROTO_TCP)
    except OSError as e:
        raise speech.ExtractionError(f"cannot resolve {parts.hostname}: {e}") from e
    for info in infos:
        addr = ipaddress.ip_address(str(info[4][0]).split("%")[0])
        if not addr.is_global:
            raise speech.ExtractionError(f"{parts.hostname} is not a public address")


class CheckedRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):  # type: ignore[no-untyped-def]
        check_public(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def fetch(url: str) -> str:
    check_public(url)
    opener = urllib.request.build_opener(CheckedRedirect)
    request = urllib.request.Request(
        url, headers={"User-Agent": USER_AGENT, "Accept": "text/html,application/xhtml+xml"}
    )
    try:
        with opener.open(request, timeout=30) as resp:
            ctype = resp.headers.get_content_type()
            if ctype not in ("text/html", "application/xhtml+xml"):
                raise speech.ExtractionError(f"not a web page ({ctype})")
            data = resp.read(MAX_PAGE + 1)
            charset = resp.headers.get_content_charset() or "utf-8"
    except urllib.error.HTTPError as e:
        raise speech.ExtractionError(f"the site answered {e.code} {e.reason}") from e
    if len(data) > MAX_PAGE:
        raise speech.ExtractionError("page is larger than 10 MB")
    return data.decode(charset, errors="replace")


# ── Synthesis ───────────────────────────────────────────────────────────


def kokoro_ready(timeout: float) -> bool:
    try:
        with urllib.request.urlopen(f"{KOKORO}/health", timeout=timeout) as resp:
            return resp.status == 200
    except OSError:
        return False


def tts(text: str) -> bytes:
    body = json.dumps(
        {
            "model": "kokoro",
            "input": text,
            "voice": VOICE,
            "response_format": "wav",
            "stream": False,  # a complete WAV with a correct header, for ffmpeg
        }
    ).encode()
    request = urllib.request.Request(
        f"{KOKORO}/v1/audio/speech", data=body, headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(request, timeout=900) as resp:
        return resp.read()


def write_silence(path: Path, seconds: float) -> None:
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(b"\0\0" * int(SAMPLE_RATE * seconds))


def synthesize(job_id: str, article: speech.Article) -> tuple[int, float]:
    """Write public/<job_id>.mp3; return (bytes, seconds)."""
    pieces = speech.to_pieces(article)
    with tempfile.TemporaryDirectory(dir=STATE / "tmp") as tmp_name:
        tmp = Path(tmp_name)
        silences: dict[float, Path] = {}
        listing: list[str] = []
        for i, (text, pause) in enumerate(pieces):
            wav = tmp / f"{i:05d}.wav"
            wav.write_bytes(tts(text))
            listing.append(f"file '{wav}'")
            if pause:
                if pause not in silences:
                    silences[pause] = tmp / f"silence-{pause}.wav"
                    write_silence(silences[pause], pause)
                listing.append(f"file '{silences[pause]}'")
        (tmp / "list.txt").write_text("\n".join(listing) + "\n")
        mp3 = tmp / "episode.mp3"
        tags = {
            "title": article.title,
            "artist": article.author or article.site or FEED_TITLE,
            "album": FEED_TITLE,
            "genre": "Podcast",
            "comment": article.url,
            "date": str(datetime.now(UTC).year),
        }
        subprocess.run(
            ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y"]
            + ["-f", "concat", "-safe", "0", "-i", str(tmp / "list.txt")]
            + ["-ac", "1", "-c:a", "libmp3lame", "-b:a", "64k", "-id3v2_version", "3"]
            + [arg for k, v in tags.items() if v for arg in ("-metadata", f"{k}={v}")]
            + [str(mp3)],
            check=True,
            capture_output=True,
            timeout=1800,
        )
        probe = subprocess.run(
            [
                "ffprobe",
                "-v",
                "error",
                "-show_entries",
                "format=duration",
                "-of",
                "default=noprint_wrappers=1:nokey=1",
                str(mp3),
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        duration = float(probe.stdout.strip())
        size = mp3.stat().st_size
        os.replace(mp3, PUBLIC / f"{job_id}.mp3")  # same filesystem: atomic
    return size, duration


# ── Feed ────────────────────────────────────────────────────────────────


def write_feed() -> None:
    """Rewrite public/feed.xml from the done jobs (RSS 2.0 + iTunes tags)."""
    ET.register_namespace("itunes", ITUNES)
    ET.register_namespace("atom", ATOM)
    base = feed_base()

    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")

    def add(parent: ET.Element, tag: str, body: str = "", **attrs: str) -> ET.Element:
        el = ET.SubElement(parent, tag, {k: XML_INVALID.sub("", v) for k, v in attrs.items()})
        if body:
            el.text = XML_INVALID.sub("", body)
        return el

    add(channel, "title", FEED_TITLE)
    add(channel, "link", f"{base}/feed.xml")
    add(channel, "description", "Articles queued for listening, read aloud by Kokoro.")
    add(channel, "language", "en-us")
    add(channel, "lastBuildDate", format_datetime(datetime.now(UTC)))
    add(channel, f"{{{ATOM}}}link", href=f"{base}/feed.xml", rel="self", type="application/rss+xml")
    add(channel, f"{{{ITUNES}}}author", FEED_TITLE)
    add(channel, f"{{{ITUNES}}}explicit", "false")
    add(channel, f"{{{ITUNES}}}category", text="Technology")
    # Keeps the feed out of Apple's public directory; it is private by URL.
    add(channel, f"{{{ITUNES}}}block", "Yes")
    if (PUBLIC / "cover.png").exists():
        image = add(channel, "image")
        add(image, "url", f"{base}/cover.png")
        add(image, "title", FEED_TITLE)
        add(image, "link", f"{base}/feed.xml")
        add(channel, f"{{{ITUNES}}}image", href=f"{base}/cover.png")

    with db() as conn:
        rows = conn.execute(
            "SELECT * FROM jobs WHERE status = 'done' ORDER BY published DESC"
        ).fetchall()
    for row in rows:
        item = add(channel, "item")
        add(item, "title", row["ep_title"])
        add(item, "guid", row["id"], isPermaLink="false")
        add(item, "pubDate", format_datetime(datetime.fromtimestamp(row["published"], UTC)))
        source = row["url"] or "pasted text"
        add(item, "description", f"{row['ep_summary']}\n\nSource: {source}")
        if row["url"]:
            add(item, "link", row["url"])
        add(
            item,
            "enclosure",
            url=f"{base}/{row['id']}.mp3",
            length=str(row["bytes"]),
            type="audio/mpeg",
        )
        add(item, f"{{{ITUNES}}}duration", str(round(row["duration"])))
        add(item, f"{{{ITUNES}}}explicit", "false")

    ET.indent(rss)
    tmp = PUBLIC / ".feed.xml.tmp"
    ET.ElementTree(rss).write(tmp, encoding="utf-8", xml_declaration=True)
    os.replace(tmp, PUBLIC / "feed.xml")


def prune() -> None:
    """Delete episodes (and their MP3s) and failed jobs older than the retention."""
    cutoff = time.time() - RETENTION_DAYS * 86400
    with db() as conn:
        old = conn.execute(
            "SELECT id FROM jobs WHERE (status = 'done' AND published < ?) "
            "OR (status = 'failed' AND created < ?)",
            (cutoff, cutoff),
        ).fetchall()
        for row in old:
            (PUBLIC / f"{row['id']}.mp3").unlink(missing_ok=True)
            conn.execute("DELETE FROM jobs WHERE id = ?", (row["id"],))
    if old:
        log(f"pruned {len(old)} jobs older than {RETENTION_DAYS} days")


# ── Worker ──────────────────────────────────────────────────────────────


def process(job: sqlite3.Row) -> None:
    started = time.monotonic()
    try:
        if job["url"]:
            article = speech.extract_html(fetch(job["url"]), job["url"])
            if job["title"] and article.title == "Untitled article":
                article.title = job["title"]
        else:
            article = speech.from_text(job["text"], job["title"] or "")
        if article.words > MAX_WORDS:
            raise speech.ExtractionError(
                f"{article.words} words is over the {MAX_WORDS}-word limit (about 3 hours of audio)"
            )
        deadline = time.monotonic() + 600  # Kokoro may still be starting after a boot
        while not kokoro_ready(timeout=5):
            if time.monotonic() > deadline:
                raise RuntimeError(f"Kokoro at {KOKORO} is not answering")
            time.sleep(10)
        size, duration = synthesize(job["id"], article)
    except Exception as e:
        reason = str(e) if isinstance(e, speech.ExtractionError) else f"{type(e).__name__}: {e}"
        if isinstance(e, subprocess.CalledProcessError):
            err = e.stderr or ""
            if isinstance(err, bytes):  # ffmpeg's is bytes, ffprobe's (text=True) str
                err = err.decode(errors="replace")
            reason += f" — {err[-300:]}"
        with db() as conn:
            conn.execute(
                "UPDATE jobs SET status = 'failed', reason = ? WHERE id = ?",
                (reason[:1000], job["id"]),
            )
        log(f"failed id={job['id']} reason={reason[:300]!r}")
        return
    with db() as conn:
        conn.execute(
            "UPDATE jobs SET status = 'done', ep_title = ?, ep_summary = ?, published = ?, "
            "bytes = ?, duration = ? WHERE id = ?",
            (article.title, speech.intro(article), time.time(), size, duration, job["id"]),
        )
    took = time.monotonic() - started
    log(
        f"done id={job['id']} words={article.words} audio={duration:.0f}s "
        f"took={took:.0f}s ({duration / took:.1f}x real time) title={article.title!r}"
    )


def worker() -> None:
    try:
        while True:
            job = claim()
            if job is not None:
                process(job)
            write_feed()
            prune()
            if job is None:
                # Woken by enqueue(); the hourly timeout is the prune clock.
                WAKE.wait(3600)
                WAKE.clear()
    except BaseException:
        traceback.print_exc()
        os._exit(1)  # let systemd restart the whole service, intake included


def main() -> None:
    shutil.rmtree(STATE / "tmp", ignore_errors=True)  # WAVs of a job cut off mid-run
    (STATE / "tmp").mkdir(parents=True, exist_ok=True)
    PUBLIC.mkdir(parents=True, exist_ok=True)
    if COVER:
        shutil.copyfile(COVER, PUBLIC / "cover.png")
    init_db()
    write_feed()  # picks up a changed cover without waiting for an episode
    threading.Thread(target=worker, name="worker", daemon=True).start()
    server = ThreadingHTTPServer((BIND, PORT), Intake)
    log(f"listening on {BIND}:{PORT}, kokoro={KOKORO} voice={VOICE}")
    server.serve_forever()


if __name__ == "__main__":
    sys.exit(main())
