# post_tool_call audit hook for hermes-agent. Wrapped by pkgs.writeScript in
# hermes.nix (which prepends the interpreter shebang) so it runs from the
# read-only /nix/store inside the container — the agent cannot rewrite it.
#
# Receives the hook payload as JSON on stdin:
#   {tool_name, args, result, duration_ms, session_id, task_id, tool_call_id}
# Appends ONE JSON line to $HERMES_HOME/logs/audit.jsonl. Deliberately logs
# an args DIGEST, never argument or result content — the audit trail must
# not become a second copy of mail bodies / note text.
#
# post_tool_call returns are ignored by hermes, and a crashing hook is
# logged-and-skipped, so this is fire-and-forget — but it still swallows
# every exception itself: an audit failure must never affect the agent.
import hashlib
import json
import os
import sys


def main() -> None:
    payload = json.loads(sys.stdin.read() or "{}")

    tool = str(payload.get("tool_name") or "")
    # MCP tools are registered as mcp__<server>__<tool>; builtin tools have
    # no prefix. Split so the log is greppable per integration.
    server = "builtin"
    if tool.startswith("mcp__"):
        parts = tool.split("__", 2)
        if len(parts) == 3:
            server = parts[1]

    args_canon = json.dumps(
        payload.get("args") or {}, sort_keys=True, default=str
    ).encode("utf-8")

    # Outcome is best-effort: tool handlers return JSON strings, and errors
    # are returned (not raised) as {"error": ...}-shaped strings.
    outcome = "ok"
    result = payload.get("result")
    if isinstance(result, str) and result.lstrip().startswith("{"):
        try:
            parsed = json.loads(result)
            if isinstance(parsed, dict) and (
                "error" in parsed or parsed.get("success") is False
            ):
                outcome = "error"
        except ValueError:
            pass

    from datetime import datetime, timezone

    entry = {
        "ts": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "server": server,
        "tool": tool,
        "args_digest": hashlib.sha256(args_canon).hexdigest()[:16],
        "args_bytes": len(args_canon),
        "outcome": outcome,
        "duration_ms": payload.get("duration_ms"),
        "session": payload.get("session_id"),
        "call": payload.get("tool_call_id"),
    }

    home = os.environ.get("HERMES_HOME") or os.path.expanduser("~/.hermes")
    log_dir = os.path.join(home, "logs")
    os.makedirs(log_dir, exist_ok=True)
    # Explicit 0660 on create: whoever fires the hook first would otherwise
    # set the mode from their umask (owner rw + group for the forwarder's
    # hermes-group tail; never world-readable).
    fd = os.open(
        os.path.join(log_dir, "audit.jsonl"),
        os.O_CREAT | os.O_APPEND | os.O_WRONLY,
        0o660,
    )
    with os.fdopen(fd, "a", encoding="utf-8") as f:
        f.write(json.dumps(entry) + "\n")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
