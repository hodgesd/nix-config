# Path-jailed Obsidian vault MCP server (Phase 1). Runs on the Mac mini
# as a launchd user agent (iCloud files belong to the login session),
# bound to loopback; the tailnet sees it only through `tailscale serve`.
#
# Security model, same philosophy as the Phase-2 UniFi server: this file
# is short enough to review and the dangerous tools DO NOT EXIST. There
# is no delete, no arbitrary write, no overwrite: the only free-text
# write is append_inbox (create-only, O_EXCL, into Inbox/), and
# create_daily_note is idempotent (existing note is never touched).
# Every path is resolved and prefix-checked against the vault root;
# dotfiles (.obsidian, .git, .trash, …) are invisible at every layer.
#
# argv: <vault-path> [port]
# env:  VAULT_MCP_TOKEN (bearer token, required — from sops)
import hmac
import os
import re
import sys
from datetime import date, datetime
from pathlib import Path

import uvicorn
from fastmcp import FastMCP

VAULT = Path(sys.argv[1]).resolve()
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 9102
TOKEN = os.environ["VAULT_MCP_TOKEN"]
if not VAULT.is_dir():
    raise SystemExit(f"vault not found: {VAULT}")
if len(TOKEN) < 32:
    raise SystemExit("refusing to start with a short/empty VAULT_MCP_TOKEN")

MAX_READ = 100_000  # chars per note returned to the model
MAX_RESULTS = 30


def _jail(rel: str) -> Path:
    """Resolve a vault-relative path; refuse escapes and hidden entries."""
    if any(part.startswith(".") for part in Path(rel).parts):
        raise ValueError("hidden files and folders are not accessible")
    p = (VAULT / rel).resolve()  # resolves symlinks — escapes surface here
    if p != VAULT and VAULT not in p.parents:
        raise ValueError("path escapes the vault")
    return p


def _slug(text: str) -> str:
    s = re.sub(r"[^A-Za-z0-9 -]", "", text)[:40].strip()
    return re.sub(r"\s+", " ", s) or "note"


mcp = FastMCP("vault")


@mcp.tool
def append_inbox(text: str, title: str = "") -> str:
    """File a capture as a NEW note in Inbox/ (GTD). Never overwrites."""
    ts = datetime.now()
    name = f"{ts:%Y-%m-%d %H%M} {_slug(title or text)}.md"
    target = _jail(f"Inbox/{name}")
    target.parent.mkdir(exist_ok=True)
    body = f"{text.strip()}\n\n— captured via Hermes {ts:%Y-%m-%d %H:%M}\n"
    # O_EXCL: existing files are sacred; a same-minute collision gets a suffix.
    for candidate in (target, target.with_name(target.stem + " 2.md")):
        try:
            fd = os.open(candidate, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644)
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                f.write(body)
            return f"created Inbox/{candidate.name}"
        except FileExistsError:
            continue
    raise ValueError("could not create a unique inbox note")


@mcp.tool
def create_daily_note(day: str = "") -> str:
    """Create today's (or YYYY-MM-DD's) daily note. Idempotent: an
    existing note is reported, never modified."""
    # Root-level YYYY-MM-DD.md, matching the vault's actual convention
    # (periodic-notes config: folder "", format "", no template — and
    # years of existing dailies at the root). A Daily/ folder here would
    # fight Obsidian's own "open today's note".
    d = date.fromisoformat(day) if day else date.today()
    target = _jail(f"{d:%Y-%m-%d}.md")
    if target.exists():
        return f"already exists: {target.name}"
    template = VAULT / "Templates" / "Daily Note.md"
    body = (
        template.read_text(encoding="utf-8")
        if template.exists()
        else f"# {d:%A, %B %-d %Y}\n\n## Calendar\n\n## Tasks\n\n## Notes\n"
    )
    body = body.replace("{{date}}", f"{d:%Y-%m-%d}").replace(
        "{{title}}", f"{d:%A, %B %-d %Y}"
    )
    fd = os.open(target, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(body)
    return f"created {target.name}"


@mcp.tool
def append_to_daily(text: str, section: str = "") -> str:
    """Append text to TODAY's daily note (created from the template if
    missing). Append-only — existing content is never modified. The
    logging workhorse: gym sets, fuel stops, quick journal lines."""
    today = f"{date.today():%Y-%m-%d}.md"
    target = _jail(today)
    if not target.exists():
        create_daily_note.fn()
    stamp = f"{datetime.now():%H:%M}"
    block = (f"\n### {section}\n" if section else "\n") + f"- {stamp} — {text.strip()}\n"
    with open(target, "a", encoding="utf-8") as f:
        f.write(block)
    return f"appended to {today}" + (f" under '{section}'" if section else "")


@mcp.tool
def read_note(path: str) -> str:
    """Read one note by vault-relative path (markdown/text only)."""
    p = _jail(path)
    if p.suffix.lower() not in (".md", ".txt", ".canvas"):
        raise ValueError("only markdown/text notes are readable")
    return p.read_text(encoding="utf-8", errors="replace")[:MAX_READ]


@mcp.tool
def search_notes(query: str, folder: str = "") -> list[dict]:
    """Case-insensitive substring search over note names and contents.
    Returns path + a matching line per hit."""
    root = _jail(folder) if folder else VAULT
    q = query.lower()
    hits: list[dict] = []
    for p in sorted(root.rglob("*.md")):
        rel = p.relative_to(VAULT)
        if any(part.startswith(".") for part in rel.parts):
            continue
        if q in p.stem.lower():
            hits.append({"path": str(rel), "match": "(title)"})
        else:
            try:
                for line in p.read_text(encoding="utf-8", errors="replace").splitlines():
                    if q in line.lower():
                        hits.append({"path": str(rel), "match": line.strip()[:160]})
                        break
            except OSError:
                continue
        if len(hits) >= MAX_RESULTS:
            break
    return hits


@mcp.tool
def list_notes(folder: str = "") -> list[str]:
    """List notes and subfolders one level down from a vault folder."""
    root = _jail(folder) if folder else VAULT
    out = []
    for p in sorted(root.iterdir()):
        if p.name.startswith("."):
            continue
        out.append(p.name + "/" if p.is_dir() else p.name)
    return out[:200]


# Bearer auth as a plain ASGI wrapper — deliberately independent of any
# fastmcp auth API: constant-time compare, 401 on anything else. The
# tailnet (via serve) is the outer wall; this token is the inner one.
_inner = mcp.http_app()


async def app(scope, receive, send):
    if scope["type"] == "http":
        auth = dict(scope.get("headers") or []).get(b"authorization", b"")
        if not hmac.compare_digest(auth, b"Bearer " + TOKEN.encode()):
            await send(
                {"type": "http.response.start", "status": 401, "headers": []}
            )
            await send({"type": "http.response.body", "body": b"unauthorized"})
            return
    # Non-http scopes (lifespan) pass straight through — the inner app's
    # session manager needs its startup hooks to run.
    await _inner(scope, receive, send)


if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=PORT, lifespan="on")
