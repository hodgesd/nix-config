# Phase 4 — Apple bridge (Reminders + Calendar): close-out

Built and deployed 2026-08-30. Second bridge on the mini, reusing every
Phase-1 pattern (launchd user agent, ProcessType=Interactive, bearer
ASGI wrapper, tailscale serve, store-free token, one egress hole).

## Design decisions (and why they differ from the phase prompt)

- **Calendar is READ-ONLY in v1.** The reviewer's "Hermes Review
  staging calendar" was rejected with Derrick: events in a shadow
  calendar aren't real, and the staging pattern only fits reminders
  (which already have inbox semantics). "Schedule X" becomes a staged
  *reminder* Derrick converts in one tap; direct event creation
  (single allowlisted calendar + in-chat confirm) can be added later if
  that friction proves real. `create_event` does not exist in the file.
- **Reminder writes: Derrick's real `Inbox` list, titles marked
  `#hermes`** (revised same-day from the "Hermes Review" staging list —
  a second inbox is antithetical to GTD's single-inbox principle, and
  the safety property was never the quarantine list but the tool shape:
  create-only, no delete, and `complete_reminder` scoped to
  #hermes-marked items only. AppleScript cannot set real tags; the
  marker lives in the NOTES field — revised again same-day from title-suffix, keeping titles clean.) The obsolete "Hermes Review" list can be
  deleted in Reminders.
- **Reads via icalBuddy (brew), writes via /usr/bin/osascript** —
  nixpkgs has no pyobjc-EventKit and Swift-in-nix is a project.
  Deliberate TCC win: read grants key on the *stable brew binary*, so
  they survive nix env rebuilds; only the osascript Automation grant
  keys on the python env's store path.
- **[WORK] calendar: not built** — governance-gated on the
  employer-policy question (v1.1.1). Personal-only brief until answered.

## TCC runbook (the operational knowledge this phase bought)

- First tool calls pop dialogs in the mini's GUI session: icalBuddy →
  Reminders, icalBuddy → Calendars, python → Reminders (Automation).
- **Trap found live: macOS Calendar access is split "Add Only" vs
  "Full Access", and icalBuddy under the default returns `error: No
  calendars.`** Fix: System Settings → Privacy & Security → Calendars →
  icalBuddy → Full Access.
- After a `just update` that changes the python env, the *Automation*
  grant re-prompts (reminder writes hang → tool timeout → brief says
  "unavailable"). Re-approve at the screen. icalBuddy reads are immune
  (stable binary) unless brew upgrades it.

## Validation (2026-08-30)

1. Four tools exactly, locally and over the tailnet from the VM.
2. Reminders: real data read; "Phase 4 TCC validation" created with due date (visible on iPhone; made under the pre-revision staging list — delete it with that list).
3. Calendar: real events across calendars after the Full Access fix.
   Polish note: an event present in two calendars appears twice —
   acceptable (the model dedups), revisit with `-ea`/calendar filters
   if it annoys.
4. 401 without token via tailnet; egress hole `mini:8322` live.
5. **Cron:** `daily-note` replaced by `morning-brief` (05:30 CT,
   deliver telegram, workdir /data/workspace): daily note + events +
   reminders + WAN line, each section degrading to "unavailable".
6. Left for Derrick: Telegram "remind me to test phase 4 tomorrow at
   9am" → Hermes Review on iPhone + `mcp__apple__create_reminder`
   digest in `hermes-audit`; "what's on my calendar tomorrow?"; the
   05:30 brief itself.

## Disable / revoke

| Action | How |
|---|---|
| Hermes loses apple tools | remove `./apple.nix` from VM imports, deploy |
| Stop the bridge | `launchctl bootout gui/$UID/org.nixos.apple-mcp` (undeclared) or remove the agent block + rebuild |
| Un-serve | `tailscale serve --https=8322 off` on the mini |
| Revoke | rotate `apple-mcp-token` in both secrets, redeploy both hosts |
| Back to bare daily note | recreate the old cron prompt via `hermes cron` CLI |

## Credential inventory (adds one)

| Name | Where | Scope |
|---|---|---|
| `apple-mcp-token` | sops `secrets/mini.yaml` + `hermes-env` | Bearer for the apple bridge only: reads, Inbox creates (#hermes-marked notes), move-any (Tier 1, revisit at 3a), marker-scoped complete |
