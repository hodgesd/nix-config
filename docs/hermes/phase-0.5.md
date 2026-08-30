# Phase 0.5 — Containment gate: close-out

Built and deployed 2026-08-30. Commits: `f653fdc` (gate 1), `3c243fc`
(gate 2), `7a162dd` (gate 3) + follow-up comment fix.

## What was built

| Gate | Mechanism |
|---|---|
| 1 — minimal Telegram surface | `platform_toolsets.telegram = [messaging todo vision]`. Dropped: terminal, web, browser, file, skills, cronjob, image, tts. Operator surface = `hermes` CLI on the VM over SSH (full preset, deliberately). |
| 2 — default-deny egress | `hermes-egress.nix`: iptables/ip6tables OUTPUT chain keyed to `-m owner --uid-owner hermes` (every agent process runs as that UID). Allow: loopback, established, port 53; reject RFC1918 + 100.64/10 + link-local/ULA **before** allowing tcp/443 to public addresses; log-then-reject the rest (`hermes-egress-drop` in the journal). Chosen over bridge networking because upstream hardcodes `--network=host` with no option (verified at pinned rev and HEAD); UID-scoping is per-workload and survives flake updates. |
| 3 — immutable config/policy | Read-only binds into the container: host `config.yaml` (activation merge rewrites in place → declared changes propagate), `AGENTS.md` from the nix store (policy edits change the store path → container auto-recreates), and empty ro shadows over `.hermes.md`/`HERMES.md` (they'd outrank AGENTS.md in the context loader). `fallback_providers = []` explicitly — fail closed to Anthropic. |

## What remains agent-writable (by design)

Sessions, logs (incl. `audit.jsonl` — tamper-EVIDENT, not -proof),
memories, SOUL.md/MEMORY.md (agent-managed identity/memory; policy
authority lives in the un-outrankable ro AGENTS.md).

## Validation results (2026-08-30)

1. **Gate 3 writes fail:** `config.yaml`, `AGENTS.md`, and `.hermes.md`
   creation all EROFS as the hermes user; AGENTS.md reads the policy;
   `platform_toolsets` and `fallback_providers: []` present in the
   container's config view.
2. **Gate 2 egress:** 192.168.1.1:443 rejected, remote tailnet node
   (adguard 100.97.42.82) rejected on 443 and 3000, 1.1.1.1:80 rejected —
   **confirmed by the chain's packet counters**, not just connection
   errors; api.telegram.org:443 and api.anthropic.com:443 connect;
   long-polling verified live (two established sockets to a Telegram DC
   from the hermes process).
3. **Root in container:** steady state has NO root process — PID 1 is
   the gateway as `hermes`. Root exists only during container-recreation
   bootstrap (the upstream entrypoint apt-installs runtime deps as root,
   with unrestricted egress for those minutes — accepted, documented).
4. **Services:** hermes-agent + hermes-audit-forwarder active; watchdog
   path (`docker inspect`) unchanged and green.
5. **Left for Derrick (manual):** ask the bot to run a shell command /
   fetch a URL → must fail at the tool layer; normal chat works;
   optional full-VM reboot test (firewall chain and container creation
   are both deterministic activation/boot paths).

## Findings during validation (both fixed)

- **The AGENTS.md ro shadow can be silently detached from the host**:
  removing `/var/lib/hermes/workspace/AGENTS.md` (host side, same
  filesystem as the volume) unlinks the bind's mountpoint dentry and the
  path becomes agent-writable again. Found because the close-out plan
  itself said to "remove the stale copy" — it did exactly that. Fixed by
  container recreation; the file is the mount anchor and must never be
  removed while the container runs (hermes.nix comment corrected).
  Watch item: anything that recreates that file path host-side.
- **Bootstrap root egress**: the recreate-time apt bootstrap runs as
  container root, outside the hermes-UID rules. Bounded (minutes, only
  at recreation), needed for the bootstrap to work at all; noted here
  rather than "fixed".

## Known residuals (accepted, tracked)

- DNS (port 53 anywhere) is an exfil channel — closed by the follow-up
  **named-domain egress proxy** stage, which also narrows 443 from
  "any public" to Telegram+Anthropic only.
- Loopback allow means the agent UID can reach VM-local listeners
  (that's also the future localhost-MCP path); local services carry
  their own auth.
- Inbound: owner-match can't filter listeners; `tailscale0` is trusted,
  so the agent UID could bind a tailnet-visible port. Tailnet-only
  exposure; revisit with the Tailscale-sidecar question.
- In-container `hermes config set` / `/personality` saves now fail —
  config is declarative-only, on purpose.

## Disables (one line each)

| Gate | Disable |
|---|---|
| 1 | remove the `platform_toolsets` line, deploy |
| 2 | remove `./hermes-egress.nix` from the host imports, deploy |
| 3 | remove the `container.extraVolumes` block (and restore `fallback_providers` deliberately if wanted), deploy |

## Credential inventory

Unchanged from Phase 0. `OPENROUTER_API_KEY` is now unused (fallback
dropped) — optional cleanup from the sops blob.
