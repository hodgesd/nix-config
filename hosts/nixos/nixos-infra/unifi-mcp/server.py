# Lean read-only UniFi MCP server (Phase 2).
#
# The whole security model of this file is that it is SHORT and does only
# reads: the sole POST is the login handshake; every tool is a GET with
# response fields trimmed before they reach the model. There is no
# mutation code to disable — it does not exist. The account it logs in
# with (hermes-viewer) is View Only, so even a bug here cannot write:
# tool layer and account layer fail independently.
#
# Runs under majordouble.mcpServers (DynamicUser, ProtectSystem=strict),
# bound to loopback; hermes reaches it via http://127.0.0.1:9101/mcp/.
# argv: <console-url> <ca-pem-path>   (non-secret config)
# env:  UNIFI_USERNAME, UNIFI_PASSWORD (sops), UNIFI_SITE (optional)
import os
import ssl
import sys
import threading

import httpx
from fastmcp import FastMCP

CONSOLE = sys.argv[1].rstrip("/") if len(sys.argv) > 1 else "https://192.168.1.1"
CA_PEM = sys.argv[2] if len(sys.argv) > 2 else None
SITE = os.environ.get("UNIFI_SITE", "default")
API = f"/proxy/network/api/s/{SITE}"

# The console cert is self-signed with CN=unifi.local and we connect by
# IP, so hostname verification can never pass — the PIN is the guarantee:
# we trust exactly the certificate fetched from the console at build
# time, nothing else. If the console regenerates its cert, this server
# fails closed until console-cert.pem is refreshed.
ctx = ssl.create_default_context()
if CA_PEM:
    ctx.load_verify_locations(CA_PEM)
    ctx.check_hostname = False
    # The console cert is a self-signed LEAF with no basicConstraints.
    # Two verifier adjustments make exact-leaf pinning work: partial
    # chain (accept a trusted non-CA cert when it matches the presented
    # leaf — that exact match IS the pin) and clearing VERIFY_X509_STRICT,
    # which python 3.13 turns on by default and which rejects the
    # console's malformed cert outright ("invalid CA certificate").
    ctx.verify_flags |= ssl.VERIFY_X509_PARTIAL_CHAIN
    ctx.verify_flags &= ~ssl.VERIFY_X509_STRICT
else:
    raise SystemExit("refusing to start without a pinned CA (argv[2])")

client = httpx.Client(base_url=CONSOLE, verify=ctx, timeout=15)
_login_lock = threading.Lock()


def _login() -> None:
    r = client.post(
        "/api/auth/login",
        json={
            "username": os.environ["UNIFI_USERNAME"],
            "password": os.environ["UNIFI_PASSWORD"],
        },
    )
    r.raise_for_status()


def _get(path: str, params: dict | None = None) -> dict:
    r = client.get(path, params=params)
    if r.status_code == 401:
        with _login_lock:
            _login()
        r = client.get(path, params=params)
    r.raise_for_status()
    return r.json()


def _pick(items: list[dict], keys: list[str], limit: int) -> list[dict]:
    return [{k: d.get(k) for k in keys if d.get(k) is not None} for d in items[:limit]]


mcp = FastMCP("unifi")


@mcp.tool
def wan_health() -> list[dict]:
    """Status of every subsystem (wan/www/wlan/lan/vpn): state, WAN IP,
    ISP, gateway latency, client counts, throughput."""
    data = _get(f"{API}/stat/health").get("data", [])
    keys = [
        "subsystem", "status", "wan_ip", "isp_name", "isp_organization",
        "uptime", "latency", "xput_up", "xput_down", "speedtest_ping",
        "num_user", "num_guest", "num_iot", "num_ap", "num_sw", "num_gw",
        "num_adopted", "num_disconnected", "tx_bytes-r", "rx_bytes-r",
        "gw_system-stats",
    ]
    return _pick(data, keys, 20)


@mcp.tool
def list_devices() -> list[dict]:
    """UniFi devices (APs, switches, gateway): model, name, state."""
    data = _get(f"{API}/stat/device-basic").get("data", [])
    return _pick(data, ["mac", "name", "model", "type", "state", "adopted", "disabled"], 100)


@mcp.tool
def list_clients() -> list[dict]:
    """Currently connected clients: name, IP, network, wired/wifi, signal."""
    data = _get(f"{API}/stat/sta").get("data", [])
    keys = [
        "mac", "name", "hostname", "ip", "network", "is_wired", "essid",
        "ap_mac", "signal", "uptime", "oui",
    ]
    return _pick(data, keys, 200)


@mcp.tool
def recent_events(hours: int = 24, limit: int = 50) -> list[dict]:
    """Recent controller events (connects, disconnects, WAN transitions,
    admin logins). hours: look-back window, limit: max entries."""
    data = _get(
        f"{API}/stat/event", params={"within": hours, "_limit": min(limit, 200)}
    ).get("data", [])
    return _pick(data, ["datetime", "key", "subsystem", "msg"], min(limit, 200))


@mcp.tool
def network_stats() -> dict:
    """One-shot summary: per-subsystem health plus device/client counts."""
    health = _get(f"{API}/stat/health").get("data", [])
    devices = _get(f"{API}/stat/device-basic").get("data", [])
    clients = _get(f"{API}/stat/sta").get("data", [])
    return {
        "subsystems": _pick(health, ["subsystem", "status", "num_user", "latency"], 20),
        "devices_total": len(devices),
        "devices_online": sum(1 for d in devices if d.get("state") == 1),
        "clients_total": len(clients),
        "clients_wired": sum(1 for c in clients if c.get("is_wired")),
        "clients_wireless": sum(1 for c in clients if not c.get("is_wired")),
    }


if __name__ == "__main__":
    _login()
    mcp.run(transport="http", host="127.0.0.1", port=9101)
