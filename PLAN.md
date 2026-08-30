# PLAN.md — Phase 2: UniFi, read-only

Intended changes only. **Nothing is applied until you say "go".**
One human checklist item blocks the deploy (your console work, below).

## Design decision: lean purpose-built server, not sirkirby

Evaluated `sirkirby/unifi-network-mcp` per the phase prompt. Rejected on
three grounds:
1. **Surface:** 192 Network tools including create/update/delete
   mutations behind a preview-confirm flow — we'd be disabling ~185
   tools and trusting config to hold the ceiling. Our own v1.1 doctrine
   (3b broker): small-enough-to-review beats big-with-tools-disabled.
2. **Transport:** stdio-first. A stdio MCP server is spawned *inside*
   the hermes container as the hermes UID — where Phase 0.5's egress
   rules correctly reject the LAN console. Any UniFi server must be an
   HTTP service on the host under its own identity.
3. **Auth:** wants a local admin username/password; we want the official
   API-key header.

**Build instead:** `hosts/nixos/nixos-infra/unifi-mcp/server.py` —
~150 lines, `fastmcp` + `httpx` straight from the pinned nixpkgs
(verified present: fastmcp 2.12.5, mcp 1.15.0), streamable-HTTP on
`127.0.0.1:9101`, `X-API-Key` auth to the console. **No mutation code
exists in the file** — the review of one short file is the server-side
ceiling. First real consumer of Phase 0's `majordouble.mcpServers`
module (DynamicUser, ProtectSystem=strict, own env-file).

Tools (server side, mirrored client side): `list_devices`,
`list_clients`, `wan_health`, `recent_events`, `network_stats`.
Implementation reality to verify during build: the official local
Integration API (`/proxy/network/integration/v1/...`) covers
sites/devices/clients cleanly; health/ISP-metrics coverage varies by
console version — whatever the API key can't reach, the tool returns
"not available via integration API" rather than falling back to
password-auth legacy endpoints. Console TLS is self-signed → pin the
console cert (fetch once, ship as a file) rather than `verify=False`.

## Hermes wiring

```nix
services.hermes-agent.mcpServers.unifi = {
  url = "http://127.0.0.1:9101/mcp";   # loopback — allowed by hermes-egress
  tools.include = ["list_devices" "list_clients" "wan_health" "recent_events" "network_stats"];
};
```
Client-side include is defense-in-depth; the server simply has nothing
else. Note the layering win from 0.5: hermes (UID-jailed) reaches only
localhost; the MCP server (own DynamicUser, not the hermes UID) reaches
only the console with a read-only key.

## WAN watcher + new-device alert (deterministic, not agent-driven)

- `wan-watch`: systemd timer (1 min) doing external anchor probes
  (2 HTTPS heads + 1 DNS resolve; 2-of-3 fail = down) — **zero
  credentials**, detects flaps even when the console itself is
  unreachable. State transitions append to
  `/var/lib/wan-watch/events.log` with timestamp + outage duration.
  Weekly summary timer (Sun 08:00): flap count + total downtime.
- `unifi-device-watch`: 15-min timer diffing the client list via the
  same API key (same integration = same credential, per the
  one-credential-per-integration rule); new MAC → alert with MAC,
  hostname, network.
- **Alert delivery: ntfy** (`hermes-alerts` topic on the existing
  tailnet ntfy — zero credentials, matches kuma/hermes-watchdog house
  pattern). The phase doc said Telegram; direct Bot-API delivery would
  mean sharing or duplicating the bot credential with another service,
  against the separation rule. Telegram delivery of this data arrives
  properly with the deployment-declared morning brief (hermes reads the
  watcher's log/UniFi via MCP). Say the word if you want Telegram now
  anyway and I'll plan a dedicated alert-bot credential instead.

## Your checklist (blocks deploy)

1. On the UniFi console: create a **local** admin `hermes-viewer` with
   the **read-only / View Only** role (no SSO account).
2. Log in as hermes-viewer → create an **API key** under that account
   (Settings → Control Plane → Integrations, or account settings —
   varies by console version). The key inherits the account's read-only
   role — that's the account-layer denial the acceptance test proves.
3. `sops secrets/nixos-infra.yaml` → add key `unifi-hermes-key` with
   `UNIFI_API_KEY=<key>` (dotenv line).
4. Tell me the console's LAN address (I'll default to probing
   `https://192.168.1.1` if you just say "default").

## Acceptance (from the phase prompt, mapped)

- "What's my WAN status?" via Telegram → live data through the MCP
  chain (your manual test).
- Mutation attempt fails at BOTH layers: server has no mutation tool
  (tool-layer, by construction) AND a curl POST with the raw key → 403
  (account-layer — I test this directly).
- Simulated flap alert: I flip the wan-watch state file (or you pull the
  WAN cable) → ntfy alert with timestamp/duration.
- New-device: spoof/join a device or seed the known-MAC state minus one
  → alert fires.
- Audit log shows the MCP calls (`mcp__unifi__*`) with digests only.
- `docs/hermes/phase-2.md` close-out.

## Files

| File | Action |
|---|---|
| `hosts/nixos/nixos-infra/unifi-mcp/server.py` | new (the whole server) |
| `hosts/nixos/nixos-infra/unifi.nix` | new (mcpServers decl, hermes wiring, wan-watch + device-watch timers, sops secret decl) |
| `hosts/nixos/nixos-infra/default.nix` | edit (import unifi.nix) |
| `secrets/nixos-infra.yaml` | you (checklist #3) |
| `docs/hermes/phase-2.md`, `runtime.md` | close-out |

Disable: remove the `./unifi.nix` import, deploy. Revoke: delete the
API key / the hermes-viewer account on the console.

## Commit plan
1. `feat(unifi): lean read-only MCP server behind majordouble.mcpServers`
2. `feat(unifi): deterministic wan-watch + new-device alerts via ntfy`
3. `docs(hermes): phase-2 close-out`

**Awaiting your "go" + the checklist items.**
