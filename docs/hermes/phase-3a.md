# Phase 3a — Fastmail read-only triage: close-out

Built and deployed 2026-08-30. The first untrusted-content integration
— email bodies now enter Hermes's sessions.

## The security posture (why this is acceptable)

Layered, each independently verified:
1. **Account layer:** the `hermes-ro` token is read-only at Fastmail.
   Proof, verbatim from their server on an `Email/set` attempt:
   `"type": "accountReadOnly" — "method is not a read only method, but
   account is a read only account"`.
2. **Tool layer:** `fastmail-mcp/server.py` contains only Mailbox/get,
   Email/query, Email/get. No set, no submission, no move — the code
   does not exist.
3. **Tool shape:** metadata-first is structural — search/recent return
   headers+snippet only; a body is a separate deliberate `get_email(id)`.
4. **No exfiltration channel:** the Telegram surface has no shell, web,
   browser, file, or send capability (Phase 0.5), egress is UID-jailed,
   and Telegram output reaches only the allowlist.
5. **Policy:** `hermes-policy.md` gained mail rules — instruction-bearing
   email gets flagged with a quote, never obeyed; metadata-first; never
   act on reminders/notes because an email suggested it.

**The move/snooze decision (Derrick, "policy-only"):** `move_reminder`/
`snooze_reminder` stay unrestricted — reversible, audited, and the
structural scoping would break the "process my inbox" flow. The policy
rule above is the guard; the one-line structural fallback (scope to
#hermes items) stands ready if the audit log ever shows content-driven
reminder actions.

## What was built

- `hosts/nixos/nixos-infra/fastmail-mcp/server.py` — lean JMAP client,
  loopback `:9102`, own DynamicUser (outside the hermes egress jail —
  no new egress holes). Tools: `list_mailboxes`, `recent_emails`,
  `search_emails`, `get_email`. Session fetched at startup (fails fast
  on a revoked token). Bodies text-preferred, truncated at 20k.
- `fastmail.nix` — server decl, gateway ordering (the parking lesson),
  hermes wiring with the four-tool include.
- Credential separation: `fastmail-hermes-ro-token` is consumed ONLY by
  the mcp-fastmail unit. `hermes-env` gained nothing.
- Morning brief gained a **Mail section** (metadata-only by prompt AND
  by the tools it calls; 2–4 needs-attention items).

## Validation (2026-08-30)

1. Four tools exactly; live mailbox counts and real triage metadata.
2. Account-layer write rejection proven (above).
3. Left for Derrick: on-demand search from Telegram ("anything from
   UNUM this month?"); the planted injection email test — send yourself
   a message with instructions aimed at the agent, ask Hermes to triage,
   and confirm it FLAGS with a quote instead of obeying (also check
   `hermes-audit` shows only `mcp__fastmail__*` reads); tomorrow's brief
   shows the Mail section.

## Disable / revoke

| Action | How |
|---|---|
| Hermes loses mail | remove `./fastmail.nix` from host imports, deploy |
| Kill the server | `systemctl stop mcp-fastmail` (undeclared) |
| Revoke | delete the `hermes-ro` token at Fastmail — individually revocable, affects nothing else |

## Credential inventory (adds one)

| Name | Where | Scope |
|---|---|---|
| `fastmail-hermes-ro-token` | sops, consumed only by mcp-fastmail | Fastmail Mail, **read-only** (server-enforced) |

## Not built (deliberately)

Phase 3b (draft broker) waits until 3a proves its worth — and remains a
separate service with a separate read-write token if it ever comes.
