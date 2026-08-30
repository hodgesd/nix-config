# Hermes runtime — containment audit & operating reference (Phase 0)

Deployment: `hosts/nixos/nixos-infra/hermes.nix`, upstream module from the
`hermes-agent` flake input, pinned at rev `3f497e2` (v0.19.x). Container
mode on the host's docker_29 daemon (`nixpkgs.overlays` maps `pkgs.docker`
→ `docker_29` because the upstream module hardcodes `pkgs.docker`).

## What the agent's shell can touch (audited 2026-08-29)

`terminal.backend = "local"` executes **inside the container** — the
container IS the sandbox. Verified against the pinned module source:

| Surface | Reality |
|---|---|
| Docker socket | **Not mounted.** No container escape via docker. |
| `/nix/store` | Mounted **read-only** (needed for the hermes package + our audit hook). |
| `/data` (= host `/var/lib/hermes`) | Read-write. Its own config, workspace, sessions, logs — including `config.yaml` and the audit log (see honesty note below). |
| Host filesystem otherwise | Not mounted. No SSH keys, no other services' state, no `/run/secrets`. |
| Secrets | Only what activation merges into `/data/.hermes/.env` (0640 `hermes:hermes`): the four hermes-env keys. Other sops secrets never enter the container. |
| Network | **`--network=host`** — the biggest residual risk. The agent's shell can originate connections as the VM: to the LAN, the NAS, the UniFi console, and every tailnet node the VM can reach. This is the prompt-injection → lateral-movement path; mitigations are dst-side (tokens, read-only accounts) and the ACL work in `tailscale-acl.md`. **Owner: Phase 0.5** (v1.1) — move the container to a default-deny-egress bridge network; the phase prompt carries the test plan (Telegram long-poll, DNS, the watchdog's `docker inspect` assumptions). |
| User | Dedicated non-privileged `hermes` user (UID mapped into the container). Not in wheel, no sudo. |

## Audit trail

Every tool call (builtin and MCP — MCP tools are named
`mcp__<server>__<tool>`) fires the `post_tool_call` hook
(`hermes-audit-hook.py`, run from the read-only store), which appends
`{ts, server, tool, args_digest, args_bytes, outcome, duration_ms, session,
call}` to `/var/lib/hermes/.hermes/logs/audit.jsonl`. **Digest only — no
argument or result content is ever logged.** A host-side unit
(`hermes-audit-forwarder`) tails the file into journald as `hermes-audit`.

```bash
hermes-audit                 # live tail (journalctl -t hermes-audit -f)
hermes-audit --since -2h     # any journalctl args pass through
```

Honesty note: the agent owns `/data`, so a fully compromised agent could
truncate `audit.jsonl` or edit `config.yaml` to drop the hook (the hook
*code* is store-read-only, its *registration* is not). The trail is
tamper-evident (gaps are visible in journald), not tamper-proof.
**v1.1.1 — worse than v1.0 stated, confirmed against the merge script:**
activation preserves agent-*added* config keys (Nix keys win, new keys
survive), `mcp_servers` is not Nix-declared, config.yaml is owned by the
agent's user, and the agent can force a restart by crashing. So config
drift does NOT fully revert on deploy — the tool ceiling is bypassable by
a compromised agent until **Phase 0.5 gate 3** (read-only bind-mounts of
config.yaml and AGENTS.md into the container) closes it.

## Provider data flow (v1.1, corrected v1.1.1)

Primary inference: Anthropic (`claude-sonnet-5`). Fallback on primary
failure (one-shot per session): OpenRouter → DeepSeek open-weights — and
it receives **full session context**. v1.1.1 correction: **OpenRouter
does not by itself guarantee US-only or fixed-provider inference** — its
routing can select among providers and apply its own fallbacks unless an
explicit provider allowlist is set and provider fallbacks are disabled;
the comment in hermes.nix previously overstated this. Phase 0.5 task 4
decides: drop `fallback_providers` (fail closed to Anthropic — the
default recommendation) or pin providers and verify end-to-end. **Voice
transcription: no provider configured** — one must be chosen and
documented here before Phase 1's voice-capture use case is enabled.

## Agent policy

`hosts/nixos/nixos-infra/hermes-policy.md` is installed as workspace
`AGENTS.md` (`documents` option) and injected into every gateway session's
system prompt — the gateway loads context files from the module-set
`terminal.cwd = /data/workspace`. Reinstalled on every activation; the repo
copy is authoritative.

## Telegram authorization

`TELEGRAM_ALLOWED_USERS` (numeric IDs, in the sops `hermes-env` blob — kept
ciphertext because this repo is public) is the **only** authorization
boundary in front of an agent with a shell. `guest_mode` is left at its
default (off). Adding Robin later:

1. Get her numeric ID (e.g. have her message @userinfobot).
2. `sops secrets/nixos-infra.yaml` → append `,<her-id>` to
   `TELEGRAM_ALLOWED_USERS` in the hermes-env blob.
3. `just deploy` — `restartUnits` on the secret restarts the agent; nothing
   else to touch.

## Declaring an MCP server (the pattern for Phases 1–6)

Two halves:

```nix
# 1. Run the server — hardened systemd unit (modules/nixos/mcp-server.nix):
majordouble.mcpServers.unifi = {
  command = "${pkgs.some-mcp-server}/bin/server";
  args = ["--transport" "http" "--host" "127.0.0.1" "--port" "9101"];
  environmentFile = config.sops.secrets.unifi-hermes-key.path;
  readWritePaths = [];   # read-only integration: writes nowhere
};

# 2. Tell Hermes about it — upstream option, tool allowlist REQUIRED:
services.hermes-agent.mcpServers.unifi = {
  url = "http://127.0.0.1:9101/mcp";
  tools.include = ["list_devices" "list_clients" "get_health"];
};
```

The tool catalog is the ceiling — `tools.include` is the per-integration
allowlist the whole security model turns on. Never ship a server without it.
(Servers for the Mac mini — Phases 1/4 — use the darwin launchd pattern
instead; that plumbing is built in whichever of those phases runs first.)

## Upgrade path (deliberate; upstream Nix support is best-effort)

```bash
# On the Mac, in nix-config — never on the VM:
nix flake update hermes-agent   # check upstream issues first
just deploy-check
just deploy
```

## Kill switches

| Scope | Action |
|---|---|
| Whole agent | `services.hermes-agent.enable = false;` + deploy (or `systemctl stop hermes-agent` on the VM for immediate-but-undeclared) |
| One MCP server | Comment out its `majordouble.mcpServers.*` + `services.hermes-agent.mcpServers.*` blocks + deploy |
| Audit forwarder | Comment out `systemd.services.hermes-audit-forwarder` + deploy (the .jsonl keeps accumulating regardless) |
| Policy | Remove the `documents."AGENTS.md"` line + deploy (delete the installed file on the VM to take effect immediately) |
| Telegram entirely | Remove `"messaging"` from `extraDependencyGroups` + deploy |
| Credentials | Revoke service-side (Anthropic console, BotFather, etc.) — independent of this repo |
