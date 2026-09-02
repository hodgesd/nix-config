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
| Network | `--network=host` (upstream hardcodes it, no option) — **mitigated since Phase 0.5** by default-deny egress keyed to the hermes UID (`hermes-egress.nix`): east-west (RFC1918/tailnet/link-local) rejected, only port 53 and public tcp/443 allowed, rest log-then-rejected. Residuals: DNS exfil (until the named-domain proxy stage), loopback access to VM-local listeners, and inbound listener binding on trusted `tailscale0` (owner-match is egress-only). See `phase-0.5.md`. |
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

Honesty note: the agent owns most of `/data`, so a fully compromised
agent could truncate `audit.jsonl` — the trail is tamper-evident (gaps
visible in journald), not tamper-proof. The config-editing bypass that
v1.1.1 confirmed (activation merge preserves agent-added keys +
agent-owned config.yaml + crash-forced restarts) is **closed since
Phase 0.5 gate 3**: config.yaml and AGENTS.md are read-only bind-mounts
in the container (plus empty ro shadows over `.hermes.md`/`HERMES.md`,
which would otherwise outrank AGENTS.md in the context loader).
Operational hazard, learned the hard way: the host file
`/var/lib/hermes/workspace/AGENTS.md` is the bind's mount anchor —
removing it host-side while the container runs silently detaches the ro
shadow. Never remove it; see `phase-0.5.md`.

## Provider data flow (v1.1, corrected v1.1.1)

Primary inference: Anthropic (`claude-sonnet-5`), and since Phase 0.5
that is the ONLY provider: `fallback_providers = []` (fail closed — an
Anthropic outage silences the bot rather than shipping session context
to whichever provider OpenRouter routes to; OpenRouter guarantees
neither US-only nor fixed-provider inference without explicit pinning).
`OPENROUTER_API_KEY` remains in the secret, unused. If a fallback ever
returns it comes with verified provider pinning. **Voice transcription:
no provider configured** — one must be chosen and documented here before
Phase 1's voice-capture use case is enabled.

## Surfaces (since Phase 0.5)

Telegram: `messaging`, `todo`, `vision` only — no terminal, web,
browser, file, skills, or cron from the phone. Operator surface: the
`hermes` CLI on the VM over SSH keeps the full default preset. Config is
declarative-only (in-container `hermes config set` / `/personality`
saves fail against the ro mount).

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

Live consumers: **unifi** (Phase 2, `hosts/nixos/nixos-infra/unifi.nix` —
five read-only tools, View-Only account, pinned console cert; see
`phase-2.md`), **vault** (Phase 1, mini-hosted bridge at `mini:8321`,
five jailed tools, bearer via `${VAULT_MCP_TOKEN}` dotenv expansion; see
`phase-1.md`), and **apple** (Phase 4, mini `mini:8322` — calendar
read-only, reminder writes Inbox-only, #hermes-marked; see
`phase-4.md` incl. the TCC runbook), and **fastmail** (Phase 3a,
VM-local `127.0.0.1:9102` — read-only at token AND code layer,
metadata-first tool shape; see `phase-3a.md`). The 05:30 cron job is
**morning-brief** (events + reminders + inbox hygiene + mail triage +
WAN + daily note), operator-
managed via the `hermes cron` CLI. Operational notes: hermes parks an MCP
server after 3 failed connects until a reconnect is requested — VM-local
servers must be ordered `Before=` the gateway (unifi.nix), and remote
ones (the mini bridge) simply need to be up; a parked server recovers on
gateway restart. **Redeploying a bridge with NEW tools requires
`systemctl restart hermes-agent`** — the gateway only refreshes an MCP
server's tool catalog on restart/reconnect, so hermes will truthfully
claim the tool doesn't exist until bounced (learned live with
move_reminder). macOS-hosted servers MUST set launchd
`ProcessType = "Interactive"` or App Nap silently starves SSE (phase-1.md).

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

## Post-phase enhancements (2026-08-30)

One batch after Phases 1/2/4 closed: **local voice transcription**
(faster-whisper `small` in-container via the `voice` dependency group —
audio never leaves the homelab; first use downloads the model over
public 443), **`wan_history`** on the unifi server (reads the wan-watch
outage log via a pid1 `BindReadOnlyPaths` mount — `/var/lib/private` is
0700 and untraversable, a trap now handled by the mcp-server module
option), **traffic-rate fields** in `list_clients`,
**`append_to_daily`** on the vault server (the logging workhorse), and
the **ntfy → ntfy.sh iOS push relay** (wake-up ping only; content stays
tailnet-local). Tool counts: unifi 6, vault 6, apple 6.

## Secrets single-writer rule (learned 2026-08-31)

The `hermes-env` blob is one sops VALUE holding many keys — edits must
go through `sops`/`sops set` against ONE checkout's copy of
`secrets/nixos-infra.yaml`. **Never `cp` a secrets file between
checkouts/worktrees**: keys added in one copy silently vanish when the
other is copied over it. That exact failure dropped both bridge tokens
from hermes-env (fastmail-era deploy) and 401'd the vault/apple bridges
until the 2026-08-31 morning brief exposed it. Symptom signature:
"MCP server X failed initial OAuth authentication ... 401" in the
gateway log while direct probes with the server-side token succeed.

## Cron delivery rule (learned 2026-09-01)

CLI-created `hermes cron` jobs MUST use an explicit target:
`--deliver telegram:<chat_id>` (your DM chat id = your Telegram user id,
first entry of TELEGRAM_ALLOWED_USERS). Bare `--deliver telegram` only
resolves for jobs created from inside a chat; from the CLI it composes
the whole brief, runs every tool, marks the run "ok" — then drops the
output with a single WARNING (`cron.scheduler: ... no delivery target
resolved for deliver=telegram`). Two mornings of briefs vanished this
way. Verification after any job (re)creation: `hermes cron run <name>`
then confirm that warning is ABSENT in `docker logs` and the message
arrived. Composed output is kept under
`/var/lib/hermes/.hermes/cron/output/<job-id>/` either way.

## Alert inventory (ntfy, tailnet-only; iOS relay via ntfy.sh wake-up ping)

| Topic | Producer | Fires |
|---|---|---|
| `hermes-alerts` | wan-watch (1 min) | WAN down/recovered with duration; Sunday 08:00 weekly summary |
| `hermes-alerts` | unifi-device-watch (15 min) | never-seen MAC joins |
| `hermes-alerts` | **hermes-sentinel (10 min)** | outcome checks, edge-triggered: mini bridges' auth wall (401 = healthy), `mcp-unifi`/`mcp-fastmail` active (a revoked Fastmail token = crash-loop = alert), today's morning brief ran AND delivered (judged after 05:40), nightly `homelab-backup` result |
| `hermes-watchdog` | hermes-watchdog (5 min) | agent unit/container down |
| `kuma-watchdog` | kuma-watchdog (5 min) | Uptime Kuma (i.e. the mini) unreachable |

Subscribe to all three topics. Verified 2026-09-02 by inducing a
`mcp-fastmail` stop: FAILED and recovered alerts both delivered.
Not yet covered: the mini's 04:00 Kuma backup outcome (logs only, on the
mini), Anthropic API outages while the process stays up (the sentinel's
brief check catches the daily consequence), and ntfy's own cache is 12h —
old alerts age out of `/json?poll=1`, they were still delivered.
