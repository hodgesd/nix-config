# Hermes's "podcast this": one MCP tool that queues an article on the
# read-later podcast intake (server.py), the same endpoint the iOS Share
# Sheet Shortcut calls.
#
# Why a tool and not a SKILL.md: Hermes skills are instructions the agent
# carries out with its own tools, and since Phase 0.5 the Telegram surface
# has no terminal, web or skills toolsets (hermes.nix,
# platform_toolsets.telegram). An MCP tool with a tools.include allowlist
# is how every integration here reaches Hermes, and it works the same from
# Telegram and from the Tell Hermes webhook.
#
# Credential separation, as in fastmail.nix: the intake token lives only in
# this unit's environment. Hermes sees a loopback URL and one tool.
#
# Runs under majordouble.mcpServers (own DynamicUser, outside the hermes
# egress jail), loopback 127.0.0.1:9105.
# env: PODCAST_INTAKE_TOKEN (sops), PODCAST_INTAKE_URL
import json
import os
import urllib.error
import urllib.request

from fastmcp import FastMCP

INTAKE_URL = os.environ.get("PODCAST_INTAKE_URL", "http://127.0.0.1:8095/enqueue")
TOKEN = os.environ["PODCAST_INTAKE_TOKEN"]
PORT = int(os.environ.get("PODCAST_MCP_PORT", "9105"))

mcp = FastMCP("podcast")


@mcp.tool
def podcast_this(url: str = "", text: str = "", title: str = "") -> str:
    """Queue an article for the user's private read-later podcast (it plays in
    Overcast). Use it when the user says "podcast this <url>", or asks to
    listen to an article later. Pass the article's URL, or pasted text with a
    short title. It returns as soon as the job is queued; the episode shows up
    in the feed a few minutes later."""
    payload = {k: v.strip() for k, v in {"url": url, "text": text, "title": title}.items() if v}
    if "url" not in payload and "text" not in payload:
        return "Nothing to queue: give a URL, or text with a title."
    request = urllib.request.Request(
        INTAKE_URL,
        data=json.dumps(payload).encode(),
        headers={"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=15) as resp:
            job = json.load(resp)
    except urllib.error.HTTPError as e:
        return f"The podcast intake refused it ({e.code}): {e.read(300).decode(errors='replace')}"
    except OSError as e:
        return f"The podcast intake is unreachable: {e}"
    return f"Queued (job {job['id'][:8]}). It will be in the podcast feed in a few minutes."


if __name__ == "__main__":
    mcp.run(transport="http", host="127.0.0.1", port=PORT)
