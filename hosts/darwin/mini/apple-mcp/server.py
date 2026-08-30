# Apple bridge MCP server (Phase 4): Reminders + Calendar on the mini.
#
# Same philosophy as the vault server: the file is short, and the
# dangerous tools do not exist. Calendar is READ-ONLY in v1 (no
# create_event anywhere — "schedule X" becomes a reminder instead).
# Reminder writes land ONLY in the Inbox list (GTD: one inbox), each
# carrying a #hermes marker in its notes; completion is scoped to
# marked items. No delete, no edits to anything else.
#
# Reads go through icalBuddy (EventKit — fast, structurally read-only;
# TCC Calendar+Reminders grants key on the stable brew binary). Writes
# go through /usr/bin/osascript into Reminders.app (TCC Automation
# grant). First use of each prompts once in the GUI session; a hung
# grant surfaces as a tool timeout, and the brief says "unavailable".
#
# argv: [port]   env: APPLE_MCP_TOKEN (bearer, from sops)
import hmac
import os
import subprocess
import sys
from datetime import date, datetime, timedelta

import uvicorn
from fastmcp import FastMCP

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 9103
TOKEN = os.environ["APPLE_MCP_TOKEN"]
if len(TOKEN) < 32:
    raise SystemExit("refusing to start with a short/empty APPLE_MCP_TOKEN")

ICALBUDDY = "/opt/homebrew/bin/icalBuddy"
OSASCRIPT = "/usr/bin/osascript"
# GTD: ONE inbox. Hermes writes into Derrick's real Inbox list; the
# #hermes provenance marker lives in the NOTES field (his call — titles
# stay clean; AppleScript cannot set real tags). Safety is the tool
# shape, not a quarantine list: create-only, and complete_reminder only
# touches notes-marked items.
TARGET_LIST = "Inbox"
MARKER = "#hermes"
MAX_OUT = 20_000


def _run(cmd: list[str], timeout: int = 45) -> str:
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    if r.returncode != 0:
        raise ValueError((r.stderr or r.stdout or "command failed").strip()[:300])
    return r.stdout[:MAX_OUT]


def _as_str(s: str) -> str:
    """Escape untrusted text into an AppleScript string literal body."""
    if any(ord(c) < 32 for c in s):
        raise ValueError("control characters are not allowed")
    return s.replace("\\", "\\\\").replace('"', '\\"')


mcp = FastMCP("apple")


@mcp.tool
def list_events(days_ahead: int = 1, days_back: int = 0) -> str:
    """Calendar events from days_back before today through days_ahead
    after, across all visible calendars (each entry names its calendar).
    Read-only by construction."""
    start = date.today() - timedelta(days=max(0, min(days_back, 30)))
    end = date.today() + timedelta(days=max(0, min(days_ahead, 60)))
    out = _run([
        ICALBUDDY, "-nc", "-npn", "-b", "* ", "-ps", "| — |",
        "-iep", "title,datetime,location",
        f"eventsFrom:{start:%Y-%m-%d}", f"to:{end:%Y-%m-%d}",
    ])
    return out.strip() or "no events in range"


@mcp.tool
def list_reminders(due_within_days: int = 7, list_name: str = "") -> str:
    """Uncompleted reminders. Default view: due/overdue within the
    window across all lists. With list_name (e.g. "Inbox"): EVERY
    uncompleted item in that one list, undated included — the GTD
    processing view."""
    if list_name:
        out = _run([
            ICALBUDDY, "-nc", "-npn", "-b", "* ", "-ps", "| — |",
            "-ic", list_name, "uncompletedTasks",
        ])
        return out.strip() or f"no open reminders in {list_name}"
    horizon = date.today() + timedelta(days=max(0, min(due_within_days, 60)))
    out = _run([
        ICALBUDDY, "-nc", "-npn", "-b", "* ", "-ps", "| — |",
        "-stbl",  # group under list-name headers
        f"tasksDueBefore:{horizon:%Y-%m-%d}",
    ])
    return out.strip() or "no reminders due in window"


@mcp.tool
def create_reminder(title: str, due: str = "", notes: str = "") -> str:
    """Create a reminder in the Inbox list; its notes carry a #hermes
    provenance marker. due: 'YYYY-MM-DD' or 'YYYY-MM-DD HH:MM' (local)."""
    props = [f'name:"{_as_str(title)}"']
    # Marker always rides in the notes/body, after any user notes.
    body = f"{_as_str(notes)}\\n{MARKER}" if notes else MARKER
    props.append(f'body:"{body}"')
    due_lines = ""
    if due:
        due_lines = _as_date_lines(_parse_due(due))
        props.append("due date:d")
    script = (
        f"{due_lines}"
        'tell application "Reminders"\n'
        f'  tell list "{TARGET_LIST}"\n'
        f"    make new reminder with properties {{{', '.join(props)}}}\n"
        "  end tell\n"
        "end tell\n"
    )
    _run([OSASCRIPT, "-e", script])
    return f"created in {TARGET_LIST}: {title}" + (f" (due {due})" if due else "")


def _as_date_lines(d: datetime) -> str:
    """AppleScript that leaves a date in variable d — integer components
    only (locale-proof; no user strings reach this)."""
    return (
        "set d to current date\n"
        "set day of d to 1\n"
        f"set year of d to {d.year}\nset month of d to {d.month}\n"
        f"set day of d to {d.day}\n"
        f"set time of d to {d.hour * 3600 + d.minute * 60}\n"
    )


def _parse_due(due: str) -> datetime:
    try:
        if " " in due:
            return datetime.strptime(due, "%Y-%m-%d %H:%M")
        return datetime.combine(
            date.fromisoformat(due), datetime.min.time().replace(hour=9)
        )
    except ValueError as e:
        raise ValueError(
            f"due must be YYYY-MM-DD or 'YYYY-MM-DD HH:MM': {e}"
        ) from None


@mcp.tool
def snooze_reminder(title: str, new_due: str) -> str:
    """Change a reminder's due date (any list, any reminder — a date
    edit is fully reversible and audited; same Tier-1 call as move).
    new_due: 'YYYY-MM-DD' or 'YYYY-MM-DD HH:MM' (local)."""
    d = _parse_due(new_due)
    script = (
        f"{_as_date_lines(d)}"
        'tell application "Reminders"\n'
        f'  set r to (first reminder whose name contains "{_as_str(title)}" and completed is false)\n'
        "  set oldDue to due date of r\n"
        "  set due date of r to d\n"
        '  return name of r & " [was: " & (oldDue as string) & "]"\n'
        "end tell\n"
    )
    out = _run([OSASCRIPT, "-e", script])
    return f"snoozed to {new_due}: {out.strip()}"


@mcp.tool
def move_reminder(title: str, to_list: str) -> str:
    """Move a reminder (any list, any reminder) to another EXISTING
    list. Reversible by design — nothing is deleted; the confirmation
    names exactly what moved. Unrestricted per Derrick's Tier-1 call
    (reminders = reversible low-stakes writes); re-examine this scope
    when untrusted content arrives in Phase 3a."""
    lists = _run(
        [OSASCRIPT, "-e", 'tell application "Reminders" to get name of every list']
    ).strip()
    names = [n.strip() for n in lists.split(",")]
    if to_list not in names:
        raise ValueError(f"no list named {to_list!r}; existing lists: {names}")
    script = (
        'tell application "Reminders"\n'
        f'  set r to (first reminder whose name contains "{_as_str(title)}" and completed is false)\n'
        "  set fromList to name of container of r\n"
        "  set fullName to name of r\n"
        f'  move r to list "{_as_str(to_list)}"\n'
        '  return fullName & " [from " & fromList & "]"\n'
        "end tell\n"
    )
    out = _run([OSASCRIPT, "-e", script])
    return f"moved to {to_list}: {out.strip()}"


@mcp.tool
def complete_reminder(title: str) -> str:
    """Mark a Hermes-created reminder complete — only Inbox items whose
    notes carry the #hermes marker."""
    script = (
        'tell application "Reminders"\n'
        f'  tell list "{TARGET_LIST}"\n'
        f'    set r to (first reminder whose name contains "{_as_str(title)}" and body contains "{MARKER}" and completed is false)\n'
        "    set completed of r to true\n"
        "    return name of r\n"
        "  end tell\n"
        "end tell\n"
    )
    out = _run([OSASCRIPT, "-e", script])
    return f"completed in {TARGET_LIST}: {out.strip()}"


_inner = mcp.http_app()


async def app(scope, receive, send):
    if scope["type"] == "http":
        auth = dict(scope.get("headers") or []).get(b"authorization", b"")
        if not hmac.compare_digest(auth, b"Bearer " + TOKEN.encode()):
            await send({"type": "http.response.start", "status": 401, "headers": []})
            await send({"type": "http.response.body", "body": b"unauthorized"})
            return
    await _inner(scope, receive, send)


if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=PORT, lifespan="on")
