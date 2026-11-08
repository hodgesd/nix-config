# Apple bridge MCP server (Phase 4): Reminders + Calendar on the mini.
#
# Same philosophy as the vault server: the file is short, and the
# dangerous tools do not exist. Reminder writes land ONLY in the Inbox
# list (GTD: one inbox), each carrying a #hermes marker in its notes;
# completion is scoped to marked items. Calendar writes (2026-11-07)
# touch ONE calendar (WRITE_CALENDAR): create, and edit without
# attendees or recurrence. No delete anywhere.
#
# Reads go through icalBuddy (EventKit — fast, structurally read-only).
# Writes go through /usr/bin/osascript into Reminders.app / Calendar.app
# (TCC Automation grants). TCC charges all of it to the launchd start
# script's /bin/bash (see hosts/darwin/mini/default.nix). First use of
# each prompts once in the GUI session; a hung grant surfaces as a tool
# timeout, and the brief says "unavailable".
#
# argv: [port]   env: APPLE_MCP_TOKEN (bearer, from sops)
import asyncio
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
# The only calendar Hermes may write (Derrick's iCloud calendar, his
# call 2026-11-07). Every other calendar, [WORK] included, stays
# read-only because no tool names it.
WRITE_CALENDAR = "Derrick"
MARKER = "#hermes"
# WHY: `calendar "Derrick"` picks the first calendar with that name in ANY
# account (iCloud, Google, Exchange). Refuse to write unless the name is
# unique, so a same-named calendar elsewhere never receives Hermes's writes.
_ONE_CALENDAR = (
    f'  if (count of (every calendar whose name is "{WRITE_CALENDAR}")) is not 1 then '
    f'error "need exactly one calendar named {WRITE_CALENDAR}"\n'
)
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


def _as_date_lines(d: datetime, var: str = "d") -> str:
    """AppleScript that leaves a date in variable `var` — integer
    components only (locale-proof; no user strings reach this)."""
    return (
        f"set {var} to current date\n"
        f"set day of {var} to 1\n"
        f"set year of {var} to {d.year}\nset month of {var} to {d.month}\n"
        f"set day of {var} to {d.day}\n"
        f"set time of {var} to {d.hour * 3600 + d.minute * 60}\n"
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


def _parse_when(when: str) -> tuple[datetime, bool]:
    """'YYYY-MM-DD HH:MM' -> (that time, False); 'YYYY-MM-DD' -> (midnight,
    True = all-day)."""
    try:
        if " " in when:
            return datetime.strptime(when, "%Y-%m-%d %H:%M"), False
        return datetime.combine(date.fromisoformat(when), datetime.min.time()), True
    except ValueError as e:
        raise ValueError(
            f"use 'YYYY-MM-DD HH:MM' (timed) or 'YYYY-MM-DD' (all-day): {e}"
        ) from None


@mcp.tool
def create_event(
    title: str, start: str, end: str = "", location: str = "", notes: str = ""
) -> str:
    """Create an event in Derrick's calendar (the only writable one).
    start/end: 'YYYY-MM-DD HH:MM' local, or 'YYYY-MM-DD' for all-day
    (end = last day, inclusive). No end: timed events last 1 hour, all-day
    events 1 day. No attendees, by design: inviting people sends email."""
    s, allday = _parse_when(start)
    if end:
        e, end_allday = _parse_when(end)
        if end_allday != allday:
            raise ValueError("start and end must both be timed or both all-day")
        if allday:
            e += timedelta(days=1)
    else:
        e = s + (timedelta(days=1) if allday else timedelta(hours=1))
    if e <= s:
        raise ValueError("end must be after start")
    body = f"{_as_str(notes)}\\n{MARKER}" if notes else MARKER
    props = [
        f'summary:"{_as_str(title)}"', "start date:s", "end date:e",
        f'description:"{body}"', f"allday event:{'true' if allday else 'false'}",
    ]
    if location:
        props.append(f'location:"{_as_str(location)}"')
    script = (
        f"{_as_date_lines(s, 's')}{_as_date_lines(e, 'e')}"
        'tell application "Calendar"\n'
        f"{_ONE_CALENDAR}"
        f'  tell calendar "{WRITE_CALENDAR}"\n'
        f"    make new event with properties {{{', '.join(props)}}}\n"
        "  end tell\n"
        "end tell\n"
    )
    _run([OSASCRIPT, "-e", script])
    shown_end = (e - timedelta(days=1)).date() if allday else f"{e:%Y-%m-%d %H:%M}"
    return f"created in {WRITE_CALENDAR}: {title} ({start} to {shown_end})"


@mcp.tool
def update_event(
    title: str,
    on_date: str,
    new_title: str = "",
    new_start: str = "",
    new_end: str = "",
    new_location: str | None = None,
) -> str:
    """Edit ONE event in Derrick's calendar: the event whose title contains
    `title` and that starts on on_date ('YYYY-MM-DD'). Only the new_*
    fields given change; new_start alone keeps the duration. Times:
    'YYYY-MM-DD HH:MM' local (timed events only). Refuses events with
    attendees (an edit emails every invitee) and repeating events.
    new_location="" clears the location. Notes
    are not editable (they carry the #hermes marker; change them in
    Calendar). Returns the OLD values so the edit can be undone."""
    if not title.strip():
        raise ValueError("title is required (an empty one matches every event)")
    try:
        day = date.fromisoformat(on_date)
    except ValueError as e:
        raise ValueError(f"on_date must be YYYY-MM-DD: {e}") from None
    if not any([new_title, new_start, new_end]) and new_location is None:
        raise ValueError("nothing to change")
    d0 = datetime.combine(day, datetime.min.time())
    lines = [_as_date_lines(d0, "d0"), _as_date_lines(d0 + timedelta(days=1), "d1")]
    # Every check runs before the first `set`, so a rejected edit changes
    # nothing (and the error is the whole story).
    checks, sets = [], []
    if new_start or new_end:
        if new_start:
            ns, a = _parse_when(new_start)
            if a:
                raise ValueError("new_start needs a time: 'YYYY-MM-DD HH:MM'")
            lines.append(_as_date_lines(ns, "ns"))
        if new_end:
            ne, a = _parse_when(new_end)
            if a:
                raise ValueError("new_end needs a time: 'YYYY-MM-DD HH:MM'")
            lines.append(_as_date_lines(ne, "ne"))
        if new_start and new_end and ne <= ns:
            raise ValueError("new_end must be after new_start")
        checks += [
            "if allday event of ev then error \"all-day event: change its times yourself\"",
            "set dur to (end date of ev) - (start date of ev)",
            "set ns to " + ("ns" if new_start else "start date of ev"),
            "set ne to " + ("ne" if new_end else "ns + dur"),
            'if ne is less than or equal to ns then error "end must be after start"',
        ]
        sets += [
            # Move end first when going later, so start never passes end.
            "if ns > (end date of ev) then",
            "  set end date of ev to ne",
            "  set start date of ev to ns",
            "else",
            "  set start date of ev to ns",
            "  set end date of ev to ne",
            "end if",
        ]
    if new_title:
        sets.append(f'set summary of ev to "{_as_str(new_title)}"')
    if new_location is not None:  # "" clears it
        sets.append(f'set location of ev to "{_as_str(new_location)}"')
    script = (
        "".join(lines)
        + 'tell application "Calendar"\n'
        + _ONE_CALENDAR
        + f'  tell calendar "{WRITE_CALENDAR}"\n'
        + f'    set hits to (every event whose summary contains "{_as_str(title)}" and start date \u2265 d0 and start date < d1)\n'
        + '    if (count of hits) is 0 then error "no matching event that day"\n'
        + '    if (count of hits) > 1 then error "more than one match that day; use a longer title"\n'
        + "    set ev to item 1 of hits\n"
        # WHY: changing an event with invitees makes Calendar email them
        # (Tier 2 outbound); a repeating event can't be safely edited as
        # one occurrence from AppleScript.
        + '    if (count of attendees of ev) > 0 then error "has invitees; edit it yourself"\n'
        + "    set rec to recurrence of ev\n"
        + '    if rec is not missing value and rec is not "" then error "repeating event; edit it yourself"\n'
        + "    set loc to location of ev\n"
        + '    if loc is missing value then set loc to ""\n'
        + '    set old to "was: " & summary of ev & " | " & ((start date of ev) as string) & " to " & ((end date of ev) as string) & " | " & loc\n'
        + "".join(f"    {x}\n" for x in checks + sets)
        + "    return old\n"
        + "  end tell\n"
        + "end tell\n"
    )
    out = _run([OSASCRIPT, "-e", script])
    return f"updated in {WRITE_CALENDAR}: {title} on {on_date} ({out.strip()})"


def _calendar_readable() -> bool:
    """Probe the calendar read used by list_events and log failures locally."""
    try:
        _run([ICALBUDDY, "-nc", "-li", "1", "eventsToday"], timeout=15)
        return True
    except (OSError, ValueError, subprocess.TimeoutExpired) as exc:
        print(f"calendar health probe failed: {type(exc).__name__}: {exc}", file=sys.stderr)
        return False


_inner = mcp.http_app()


async def app(scope, receive, send):
    """Serve the public calendar status; require a token for other HTTP paths."""
    # SECURITY: /healthz is the one path before the token check, so the
    # sentinel (hermes-sentinel.nix) needs no credential. It returns only
    # "ok" or "calendar unreadable", never calendar data, and like the rest
    # of this server it is reachable only on the tailnet (tailscale serve).
    if scope["type"] == "http" and scope["path"] == "/healthz":
        ok = await asyncio.to_thread(_calendar_readable)
        await send({
            "type": "http.response.start",
            "status": 200 if ok else 503,
            "headers": [(b"content-type", b"text/plain")],
        })
        await send({
            "type": "http.response.body",
            "body": b"ok" if ok else b"calendar unreadable",
        })
        return
    if scope["type"] == "http":
        auth = dict(scope.get("headers") or []).get(b"authorization", b"")
        if not hmac.compare_digest(auth, b"Bearer " + TOKEN.encode()):
            await send({"type": "http.response.start", "status": 401, "headers": []})
            await send({"type": "http.response.body", "body": b"unauthorized"})
            return
    await _inner(scope, receive, send)


if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=PORT, lifespan="on")
