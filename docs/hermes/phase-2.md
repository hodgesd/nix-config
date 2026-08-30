# Phase 2 — UniFi read-only: close-out

Built and deployed 2026-08-30.

## What was built

- **`unifi-mcp/server.py`** — the entire UniFi tool surface in one short
  reviewable file: `wan_health`, `list_devices`, `list_clients`,
  `recent_events`, `network_stats`. Only GETs (the sole POST is the
  login handshake); responses field-trimmed before reaching the model.
  Runs under `majordouble.mcpServers` (first real consumer), loopback
  `127.0.0.1:9101`, own DynamicUser.
- **Auth:** `hermes-viewer`, a local-only **View Only** admin on the
  UDM-SE, username/password from the sops `unifi-hermes-key` dotenv.
  Password (not API key) because UniFi 10.6 hides API-key creation from
  View-Only admins — and the ROLE is the account-layer guarantee, not
  the credential type. Keep that account local-only and MFA-free.
- **TLS:** pinned to the console's own cert
  (`unifi-mcp/console-cert.pem`, CN=unifi.local, expires 2028-04-30).
  The cert is a self-signed non-CA leaf, so verification needs
  `VERIFY_X509_PARTIAL_CHAIN` and clearing python 3.13's new default
  `VERIFY_X509_STRICT`. If the console regenerates its cert, the server
  **fails closed** — re-fetch the pem and redeploy.
- **`wan-watch`** — 1-min systemd timer, 2-of-3 external anchors
  (1.1.1.1, 8.8.8.8, api.telegram.org — the last exercises DNS), zero
  credentials, works even when the console is down. Transitions →
  `/var/lib/wan-watch/events.log` with duration + ntfy both edges.
  Weekly summary Sundays 08:00.
- **`unifi-device-watch`** — 15-min timer, never-seen-MAC → ntfy alert.
  Seeded silently with 55 known MACs on first run.
- Alerts: `https://ntfy.jaguar-duckbill.ts.net/hermes-alerts` —
  **subscribe to this topic.**
- Ordering: `hermes-agent` is `After=`/`Wants=` `mcp-unifi` — hermes
  parks an MCP server after 3 failed connects and won't retry until
  asked, so the server must win the startup race.

## Validation results (2026-08-30)

1. **Tool layer:** MCP client sees exactly the five tools; live
   `wan_health`/`network_stats` returned real data (WAN ok, Spectrum,
   24.107.114.39; 55 clients).
2. **Account layer:** config mutation with the raw credentials
   (create WLAN) → **403 `api.err.NoPermission`**. Nuance found and
   accepted: UniFi permits *diagnostic commands* to viewers —
   `cmd/devmgr speedtest` succeeded with the same account. So the
   account layer blocks all config writes but not diagnostics; the tool
   layer excludes every `cmd/*` endpoint regardless (no such code
   exists in server.py). Both layers hold for what matters.
3. Watchers: wan-watch ticking (state `up`), device-watch seeded,
   weekly timer armed for Sunday.
4. Left for Derrick: ask the bot "what's my WAN status?" on Telegram —
   first prompt triggers MCP discovery; `hermes-audit` should show
   `mcp__unifi__wan_health` with a digest. Subscribe to `hermes-alerts`.

Incidental finding from the first live query: the **lan subsystem
reports status "error"** and 2 of 14 devices are offline — real signal,
worth a look in the console.

## Disable / revoke

| Action | How |
|---|---|
| Disable everything | remove `./unifi.nix` from host imports, deploy |
| Kill just the MCP server | `systemctl stop mcp-unifi` (undeclared) or comment its block |
| Revoke credential | delete the `hermes-viewer` account on the console |

## Credential inventory (adds one)

| Name | Where | Scope |
|---|---|---|
| `unifi-hermes-key` | sops (`UNIFI_USERNAME`/`UNIFI_PASSWORD`) | UDM-SE local account, Network **View Only**, config-writes denied server-side |
