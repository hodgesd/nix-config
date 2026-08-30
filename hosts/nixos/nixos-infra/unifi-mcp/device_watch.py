# New-device alert (Phase 2, task 4). Runs from a systemd timer as its
# own DynamicUser: logs into the console with the same View-Only account
# as the MCP server, diffs the connected-client MAC set against state,
# and pushes an ntfy alert for anything never seen before. Read-only by
# the same two layers as server.py. First run seeds state silently.
# argv: <console-url> <ca-pem-path> <state-dir> <ntfy-url>
import os
import ssl
import sys

import httpx

CONSOLE, CA_PEM, STATE_DIR, NTFY = (
    sys.argv[1].rstrip("/"), sys.argv[2], sys.argv[3], sys.argv[4],
)
SITE = os.environ.get("UNIFI_SITE", "default")
STATE = os.path.join(STATE_DIR, "known_macs.txt")

ctx = ssl.create_default_context()
ctx.load_verify_locations(CA_PEM)
ctx.check_hostname = False  # pinned cert, IP endpoint — same as server.py

client = httpx.Client(base_url=CONSOLE, verify=ctx, timeout=15)
client.post(
    "/api/auth/login",
    json={
        "username": os.environ["UNIFI_USERNAME"],
        "password": os.environ["UNIFI_PASSWORD"],
    },
).raise_for_status()

r = client.get(f"/proxy/network/api/s/{SITE}/stat/sta")
r.raise_for_status()
current = {
    c["mac"]: c for c in r.json().get("data", []) if c.get("mac")
}

known: set[str] = set()
if os.path.exists(STATE):
    with open(STATE, encoding="utf-8") as f:
        known = {line.strip() for line in f if line.strip()}

new_macs = set(current) - known

if known and new_macs:  # `known` empty = first run: seed, don't alert
    for mac in sorted(new_macs):
        c = current[mac]
        name = c.get("name") or c.get("hostname") or c.get("oui") or "unknown"
        net = c.get("network") or "?"
        link = "wired" if c.get("is_wired") else f"wifi {c.get('essid') or '?'}"
        # ntfy is tailnet-only (tailscale serve, real LE cert): default
        # TLS verification applies — no pin needed here.
        httpx.post(
            NTFY,
            headers={
                "Title": "New device on the network",
                "Priority": "default",
                "Tags": "electric_plug",
            },
            content=f"{name} ({mac}) joined {net} via {link}.",
            timeout=10,
        )

if new_macs or not os.path.exists(STATE):
    with open(STATE, "w", encoding="utf-8") as f:
        f.write("\n".join(sorted(known | set(current))) + "\n")
