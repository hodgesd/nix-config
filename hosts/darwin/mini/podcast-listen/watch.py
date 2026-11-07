"""Queue Obsidian inbox notes tagged #listen on the read-later podcast.

Run by launchd on the mini every 15 minutes (podcast-listen.nix). Scans
<vault>/Inbox/*.md once and exits. A note with the tag is sent once:
a link capture (a URL and little else) as {"url"}, anything longer as
{"text", "title"} with the note's name as title. Sent notes are remembered
in a state file; the vault itself is never written.

usage: watch.py <vault> <state.json> <intake url>   env: PODCAST_INTAKE_TOKEN
"""

from __future__ import annotations

import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

URL_RE = re.compile(r"https?://[^\s)>\]]+")
# Inline "#listen" (not "#listening", not inside a word) or a frontmatter
# tag list that names listen.
INLINE_TAG_RE = re.compile(r"(?<![\w#/])#listen(?![\w/-])")
FRONTMATTER_RE = re.compile(r"\A---\n(.*?)\n---\n?", re.S)
FM_TAG_RE = re.compile(r"^tags:.*\blisten\b|^\s*-\s*listen\s*$", re.M)
# A note with a URL and at most this many other words is a link capture.
LINK_CAPTURE_WORDS = 40


def payload(note: str, title: str) -> dict[str, str] | None:
    """What to send for one note, or None when it is not tagged #listen."""
    fm = FRONTMATTER_RE.match(note)
    body = note[fm.end() :] if fm else note
    if not (INLINE_TAG_RE.search(body) or (fm and FM_TAG_RE.search(fm.group(1)))):
        return None
    body = INLINE_TAG_RE.sub("", body).strip()
    urls = URL_RE.findall(body)
    if urls and len(URL_RE.sub("", body).split()) <= LINK_CAPTURE_WORDS:
        return {"url": urls[0]}
    return {"text": body, "title": title}


def send(intake: str, token: str, data: dict[str, str]) -> str:
    request = urllib.request.Request(
        intake,
        data=json.dumps(data).encode(),
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=20) as resp:
        return str(json.load(resp)["id"])


def main() -> int:
    vault, state_path, intake = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
    token = os.environ["PODCAST_INTAKE_TOKEN"]
    sent: dict[str, str] = json.loads(state_path.read_text()) if state_path.exists() else {}
    failures = 0
    for path in sorted((vault / "Inbox").glob("*.md")):
        key = path.name
        if key in sent:
            continue
        data = payload(path.read_text(encoding="utf-8", errors="replace"), path.stem)
        if data is None:
            continue
        try:
            sent[key] = send(intake, token, data)
        except (urllib.error.URLError, OSError, ValueError, KeyError) as e:
            failures += 1  # tried again next run
            print(f"failed {key}: {e}", flush=True)
            continue
        print(f"queued {key} as job {sent[key]}", flush=True)
        state_path.parent.mkdir(parents=True, exist_ok=True)
        tmp = state_path.with_suffix(".tmp")
        tmp.write_text(json.dumps(sent, indent=1, sort_keys=True))
        tmp.replace(state_path)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
