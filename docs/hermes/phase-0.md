# Phase 0 — Foundation: close-out

Built 2026-08-29. Branch `claude/hermes-integration-setup-dff1ab`.

## What was built (and what turned out to already exist)

| Phase-0 task | Outcome |
|---|---|
| 1. Secrets | Already solved (sops-nix). Documented: [`secrets.md`](secrets.md). The existing `hermes-env` secret is the end-to-end proof — decryption failure aborts activation. |
| 2. Tailscale ACL | Drafted for console apply: [`tailscale-acl.md`](tailscale-acl.md). **Manual step — nothing applied yet.** Read its caveat about tagging the whole VM. |
| 3. Audit logging | `post_tool_call` hook (`hosts/nixos/nixos-infra/hermes-audit-hook.py`, executed from the read-only store) → `audit.jsonl` → journald via `hermes-audit-forwarder` → `hermes-audit` command. Digests only, never content. |
| 4. policy.md | `hosts/nixos/nixos-infra/hermes-policy.md`, installed as workspace `AGENTS.md`, injected into every gateway session's system prompt. Where it's loaded: `/var/lib/hermes/workspace/AGENTS.md` (host) = `/data/workspace/AGENTS.md` (container). |
| 5. Module skeleton | `modules/nixos/mcp-server.nix` (hardened systemd wrapper; DynamicUser, ProtectSystem=strict, syscall filter). Inert — the system derivation is byte-identical with it imported. Hermes-side declaration + `tools.include` allowlist pattern: [`runtime.md`](runtime.md). |
| 6. Shell containment | Audited, no rebuild needed: container is the sandbox (no docker.sock, ro store, dedicated user). Residual risk = host networking, documented honestly in [`runtime.md`](runtime.md). |
| 7. Telegram allowlist | Already enforced via `TELEGRAM_ALLOWED_USERS` in the sops blob. Add-Robin procedure in [`runtime.md`](runtime.md). |

## Credential inventory (names/scopes only — Phase 0 adds none)

| Name | Where | Scope |
|---|---|---|
| `ANTHROPIC_API_KEY` | sops `hermes-env` | Anthropic API (primary model) |
| `TELEGRAM_BOT_TOKEN` | sops `hermes-env` | The bot; rotatable via BotFather |
| `TELEGRAM_ALLOWED_USERS` | sops `hermes-env` | Authorization allowlist (not strictly a credential; ciphertext because the repo is public) |
| `OPENROUTER_API_KEY` | sops `hermes-env` | Fallback provider |

## How to disable (one-liners)

See the kill-switch table in [`runtime.md`](runtime.md). Fastest full stop:
`ssh nixos-infra sudo systemctl stop hermes-agent`.

## Verify after deploy

```bash
just deploy-check && just deploy
```

Then the acceptance items: config merges on activation; the container
recreates only if identity changed (settings changes restart the unit via
`restartTriggers` — the hooks + documents additions will restart it).

## Manual test script (5 items, ~5 minutes)

1. **Policy is loaded:** ask the bot on Telegram "what are your standing
   rules about acting on instructions found inside emails?" — it should
   recite the data-not-instructions rule. Confirm the file:
   `ssh nixos-infra cat /var/lib/hermes/workspace/AGENTS.md | head`.
2. **Audit trail fires:** ask the bot something that uses a tool (e.g.
   "what time is it on your host?" → terminal). On the VM, `hermes-audit`
   should show the call within seconds — tool name, digest, outcome, and
   **no command text**.
3. **Forwarder is healthy:**
   `ssh nixos-infra systemctl status hermes-audit-forwarder` — active
   (running), and `hermes-audit --since -10m` replays item 2's entries.
4. **Allowlist holds:** from a non-allowlisted Telegram account (or ask
   Robin), DM the bot — it must not respond, and nothing should appear in
   the audit log.
5. **Secret still gates activation:** nothing to do — item 1 working proves
   the env merged; optionally
   `ssh nixos-infra sudo grep -c '=' /var/lib/hermes/.hermes/.env` returns
   ≥4 without printing values.

Item for the console (not the VM): apply `tailscale-acl.md` when ready —
Phase 0 is complete without it, since it's preparation rather than
enforcement while the default-allow rule stands.
