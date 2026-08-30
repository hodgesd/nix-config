# Phase 1 — Obsidian vault (mini-hosted): close-out

Built and deployed 2026-08-30. The first Mac-side phase; the mini's
tailnet+token plumbing that Phase 4 will reuse now exists.

## What was built

- **`hosts/darwin/mini/vault-mcp/server.py`** — the whole tool surface
  in one reviewable file: `append_inbox` (create-only, O_EXCL, into
  `Inbox/`), `create_daily_note` (idempotent; **root-level
  `YYYY-MM-DD.md`**, matching the vault's real periodic-notes
  convention — a `Daily/` folder would have fought Obsidian's own
  "today's note"), `read_note`, `search_notes`, `list_notes`. No
  delete, no overwrite, no arbitrary write. Jail = resolve+prefix check;
  dotfiles/`.obsidian`/`.git` invisible; symlink escapes refused
  (tested with a planted link to /etc/hosts). Bearer auth is a plain
  ASGI wrapper (constant-time compare), independent of fastmcp's auth
  API.
- **Vault:** `Pro Pilot 2` (376 notes; there is NO vault named
  "Derrick" — Obsidian's registries on both Macs list only Pro Pilot
  and Pro Pilot 2). Pinned always-downloaded (`brctl download`), zero
  `.icloud` stubs, no second sync engine present.
- **Exposure:** launchd user agent on `127.0.0.1:9102` →
  `tailscale serve --bg --https=8321` → `https://mini.jaguar-duckbill.ts.net:8321`
  (tailnet-only). **`ProcessType = "Interactive"` is load-bearing**:
  without it App Nap throttles the asyncio loop — uvicorn logs requests
  while SSE responses never flush; clients hang against a
  healthy-looking log. Diagnosed by manual-run-works/launchd-hangs.
- **VM side:** one deliberate egress hole (`mini:8321` before the CGNAT
  reject in `hermes-egress.nix`); `services.hermes-agent.mcpServers.vault`
  with the five-tool include list; bearer token as a
  `${VAULT_MCP_TOKEN}` placeholder expanded from hermes's dotenv — the
  token never enters the nix store. Token lives encrypted in BOTH
  `secrets/mini.yaml` (server, first sops consumer on the mini) and the
  `hermes-env` blob (client).
- **05:30 daily note:** `hermes cron` job `daily-note` (operator-created
  via CLI — chat cron stays disabled), delivery `telegram`, workdir
  `/data/workspace` so the policy AGENTS.md rides along. Two timezone
  bugs fixed en route: the container ran UTC (would have fired 00:30
  CT) — fixed with container-level `--env TZ=America/Chicago` (the
  module's `environment` option merges into the dotenv, which loads too
  late for tz init); job recreated so next-run is `05:30-05:00`.

## Validation (2026-08-30)

1. Local smoke test: 401 without token; 5 tools exactly; append +
   idempotent daily note; all four jail probes refused (traversal,
   dotfile, symlink escape, parent listing).
2. Tailnet end-to-end from the VM as the hermes UID: egress hole works,
   auth wall 401s without the token, live `append_inbox` created
   `Inbox/2026-08-30 1450 phase1 validation.md` (visible on iPhone),
   jail holds over the wire, post-reload `create_daily_note` created
   `2026-08-30.md` at the root.
3. Left for Derrick: Telegram "capture: test note about widgets" →
   filed in Inbox/ + `hermes-audit` shows `mcp__vault__append_inbox`
   digest-only; the 05:30 firing tomorrow; `.icloud` stubs stay zero
   over a week.

## Open items (deliberate)

- **Backup: NOT yet solved.** Time Machine is not configured on the
  mini (`tmutil destinationinfo` empty) and the planned mini→UNAS job
  was deferred — iCloud is sync, not backup. Until this lands, vault
  history = iCloud version history + the append-only tool design.
  **Follow-up work order:** configure TM to the UNAS or build the
  one-way rsync job.
- Voice capture: still blocked on choosing a transcription provider.
- Templates: the vault has no Templates/ folder and the plugin template
  is empty — the embedded fallback template is the template. Add
  `Templates/Daily Note.md` in Obsidian any time; the tool prefers it
  automatically.
- Weekly-review packet: on-demand prompt, no infra needed; try it once
  captures accumulate.

## Disable / revoke

| Action | How |
|---|---|
| Hermes loses the vault | remove `./vault.nix` from the VM host imports (+ optionally the egress line), deploy |
| Stop the bridge | `launchctl bootout gui/$UID/org.nixos.vault-mcp` on the mini (undeclared), or remove the agent block + rebuild |
| Un-serve | `tailscale serve --https=8321 off` on the mini |
| Revoke | rotate `vault-mcp-token` in both secrets files, redeploy both hosts |
| Kill the daily note | `hermes cron rm daily-note` (CLI on the VM) |

## Credential inventory (adds one)

| Name | Where | Scope |
|---|---|---|
| `vault-mcp-token` | sops `secrets/mini.yaml` + `hermes-env` | Bearer for the vault bridge only; grants the five jailed tools, nothing else |
