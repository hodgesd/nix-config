"""Tell Hermes: the one HTTP endpoint behind the "Tell Hermes" iOS Shortcut.

The Shortcut dictates a sentence and POSTs {"text": "..."} here with a bearer
token. This service hands it to Hermes's built-in API server as one more turn
of a single persistent session (so "and also..." follow-ups have context) and
returns Hermes's answer as plain text for the watch to speak.

If Hermes has not answered within REPLY_WAIT seconds, the Shortcut gets
"On it, I'll message you when it's done." and the turn keeps running; the
answer is then pushed to the Telegram home channel through Hermes's own
webhook platform (deliver_only: no LLM call, and the bot token never leaves
Hermes).

Why this exists at all: the API server has no "answer in N seconds or hand
off" mode, no hand-off to Telegram, and does not log the request text.
Everything else (auth, sessions, approvals, toolsets) is Hermes's own.

Runs as a systemd service (tell-hermes.nix). Secrets arrive as files under
$CREDENTIALS_DIRECTORY, never as environment variables or arguments.
"""

from __future__ import annotations

import hashlib
import hmac
import json
import logging
import os
import re
import sys
import threading
import time
import urllib.error
import urllib.request
import uuid
from concurrent.futures import Future, ThreadPoolExecutor
from concurrent.futures import TimeoutError as FutureTimeout
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

# All interfaces on purpose: the ts-tell sidecar reaches this over the Docker
# bridge, and the firewall (tell-hermes.nix) admits only that range.
LISTEN_HOST = os.environ.get("TELL_LISTEN_HOST", "0.0.0.0")
LISTEN_PORT = int(os.environ.get("TELL_LISTEN_PORT", "8650"))
HERMES_API = os.environ.get("TELL_HERMES_API", "http://127.0.0.1:8642")
HERMES_WEBHOOK = os.environ.get(
    "TELL_HERMES_WEBHOOK", "http://127.0.0.1:8644/webhooks/tell-hermes-reply"
)
SESSION_ID = os.environ.get("TELL_SESSION_ID", "tell-hermes")
REPLY_WAIT = float(os.environ.get("TELL_REPLY_WAIT", "20"))
# A turn that outlives this is abandoned; approvals are denied instantly on
# the API server, so a turn is slow only when it is genuinely working.
TURN_TIMEOUT = float(os.environ.get("TELL_TURN_TIMEOUT", "600"))

ON_IT = "On it, I'll message you when it's done."
MAX_BODY = 8 * 1024
MAX_TEXT = 2000
MAX_SPOKEN = 800

# Layered on top of Hermes's own system prompt for this turn only (it is not
# stored in the session transcript).
STYLE = (
    "This request was dictated on an Apple Watch and your reply will be "
    "spoken aloud. Answer in one or two short plain sentences. No markdown, "
    "lists, links, emoji or code."
)

log = logging.getLogger("tell-hermes")


def read_credential(name: str) -> str:
    directory = os.environ.get("CREDENTIALS_DIRECTORY")
    if not directory:
        sys.exit("CREDENTIALS_DIRECTORY is not set; run under systemd LoadCredential")
    value = (Path(directory) / name).read_text().strip()
    if not value:
        sys.exit(f"credential {name!r} is empty")
    return value


TOKEN = read_credential("token")
INTERNAL = read_credential("internal")
POOL = ThreadPoolExecutor(max_workers=4, thread_name_prefix="turn")


def speakable(text: str) -> str:
    """Strip the markdown a model emits despite being told not to."""
    text = re.sub(r"```.*?```", " ", text, flags=re.S)
    text = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", text)  # [label](url) -> label
    text = re.sub(r"^\s*(?:[-*+]|\d+\.)\s+", "", text, flags=re.M)  # list markers
    text = re.sub(r"[*_`#>]", "", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text[:MAX_SPOKEN] or "Done."


def post_json(url: str, body: bytes, headers: dict[str, str], timeout: float) -> bytes:
    request = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={"Content-Type": "application/json", **headers},
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read()


def ask_hermes(text: str) -> str:
    """One turn of the persistent Tell Hermes session; returns the raw answer.

    Raw, not speakable(): a handed-off answer goes to Telegram, which can show
    the long or formatted parts the watch would have dropped.
    """
    body = json.dumps(
        {
            "model": "hermes-agent",
            "stream": False,
            "messages": [
                {"role": "system", "content": STYLE},
                {"role": "user", "content": text},
            ],
        }
    ).encode()
    raw = post_json(
        f"{HERMES_API}/v1/chat/completions",
        body,
        {"Authorization": f"Bearer {INTERNAL}", "X-Hermes-Session-Id": SESSION_ID},
        TURN_TIMEOUT,
    )
    return json.loads(raw)["choices"][0]["message"]["content"] or ""


def push_to_telegram(heard: str, reply: str) -> None:
    """Deliver a late answer via Hermes's webhook route (deliver_only)."""
    body = json.dumps({"heard": heard[:200], "reply": reply}).encode()
    timestamp = str(int(time.time()))
    # Generic HMAC V2 (webhook.py): hex HMAC-SHA256 of "<timestamp>.<body>".
    signature = hmac.new(
        INTERNAL.encode(), timestamp.encode() + b"." + body, hashlib.sha256
    )
    post_json(
        HERMES_WEBHOOK,
        body,
        {
            "X-Webhook-Timestamp": timestamp,
            "X-Webhook-Signature-V2": signature.hexdigest(),
            "X-Request-ID": uuid.uuid4().hex,
        },
        30,
    )


def finish_in_background(future: Future[str], heard: str, started: float) -> None:
    """Waits for a handed-off turn to end, then tells the user over Telegram."""
    try:
        reply = future.result().strip() or "Done."
        outcome = "finished"
    except Exception as exc:
        log.warning("handed-off turn failed: %s", type(exc).__name__)
        reply = "I couldn't finish that one."
        outcome = "failed"
    try:
        push_to_telegram(heard, reply)
        log.info(
            "%s after %.1fs, sent to Telegram", outcome, time.monotonic() - started
        )
    except Exception as exc:
        log.error(
            "%s after %.1fs, Telegram hand-off failed: %s",
            outcome,
            time.monotonic() - started,
            exc,
        )


class Handler(BaseHTTPRequestHandler):
    server_version = "tell-hermes"
    # Per socket read/write, so an idle connection cannot hold a thread
    # forever. Not the reply wait: that is a future, not a socket read.
    timeout = 30

    def log_message(self, format: str, *args: object) -> None:
        pass  # replaced by the structured lines in do_POST

    def _send(
        self, status: HTTPStatus, text: str, extra: dict[str, str] | None = None
    ) -> None:
        payload = text.encode()
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        for name, value in (extra or {}).items():
            self.send_header(name, value)
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self) -> None:
        # Liveness only (the Gatus check polls it); reveals nothing.
        if self.path in ("/", "/healthz"):
            self._send(HTTPStatus.OK, "ok")
        else:
            self._send(HTTPStatus.NOT_FOUND, "not found")

    def do_POST(self) -> None:
        if self.path != "/tell":
            self._send(HTTPStatus.NOT_FOUND, "not found")
            return

        # SECURITY: this endpoint is remote command input into an agent that
        # has a shell-capable runtime. Tailnet reachability (the ts-tell
        # sidecar) is only the first layer; this bearer check is the second
        # and runs BEFORE the body is read or parsed. compare_digest keeps the
        # comparison constant-time. The token is never logged: not here, not
        # on rejection, not in any later line.
        presented = self.headers.get("Authorization", "")
        if not hmac.compare_digest(presented.encode(), f"Bearer {TOKEN}".encode()):
            log.warning(
                "rejected: missing or wrong token (from %s)", self.client_address[0]
            )
            self._send(
                HTTPStatus.UNAUTHORIZED, "unauthorized", {"WWW-Authenticate": "Bearer"}
            )
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= MAX_BODY:
                raise ValueError("body size")
            text = json.loads(self.rfile.read(length))["text"]
            if not isinstance(text, str) or not text.strip() or len(text) > MAX_TEXT:
                raise ValueError("text")
        except (ValueError, KeyError, TypeError):
            self._send(HTTPStatus.BAD_REQUEST, 'Send JSON like {"text": "..."}.')
            return

        text = text.strip()
        started = time.monotonic()
        log.info("heard: %r", text)
        future = POOL.submit(ask_hermes, text)
        try:
            reply = speakable(future.result(timeout=REPLY_WAIT))
        except FutureTimeout:
            # Own thread, not a done-callback: that would run on this request
            # thread if the turn finished in the gap, delaying the reply.
            threading.Thread(
                target=finish_in_background, args=(future, text, started), daemon=True
            ).start()
            log.info("handed off after %.1fs", time.monotonic() - started)
            self._send(HTTPStatus.OK, ON_IT)
            return
        except Exception as exc:
            log.error("hermes failed after %.1fs: %s", time.monotonic() - started, exc)
            self._send(HTTPStatus.BAD_GATEWAY, "Hermes didn't answer.")
            return
        log.info("replied in %.1fs", time.monotonic() - started)
        self._send(HTTPStatus.OK, reply)


def main() -> None:
    logging.basicConfig(
        level=logging.INFO, format="%(levelname)s %(message)s", stream=sys.stderr
    )
    server = ThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), Handler)
    log.info("listening on %s:%d", LISTEN_HOST, LISTEN_PORT)
    server.serve_forever()


if __name__ == "__main__":
    main()
