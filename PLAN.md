# PLAN.md — Phase 4: Apple bridge (Reminders + Calendar on the mini)

Intended changes only. **Nothing is applied until you say "go".**

## What Phase 4 unlocks (the use cases)

- **"Remind me to stow the gear-pin blocks writeup Friday"** from
  Telegram → a real Apple Reminder with a due date, on your iPhone
  seconds later.
- **A real morning brief at 05:30**: today's calendar + due/overdue
  reminders + the daily note + a WAN health line — one Telegram message
  (replacing the placeholder sections in the current daily-note job).
- **Email→task** (once 3a lands): "turn that UNUM email into a task".
- **Calendar-aware answers**: "what's my day look like Thursday?",
  travel-day scaffolding, conflicts between family events and trips.
- **v1 write-safety**: everything Hermes creates lands in a dedicated
  "Hermes Review" reminders list + calendar — your real lists/calendars
  are read-only to it until observed trust promotes it.
- **[WORK] calendar in the brief — governance-gated, not built yet**:
  your Outlook ICS subscription is readable via the same bridge, but
  per v1.1.1 that waits for your explicit yes on the employer-policy
  question (LLM processing + Telegram delivery of work data). Default:
  personal-only.

## Design (research-driven)

**AppleScript via `osascript`, not EventKit bindings.** nixpkgs has no
pyobjc-EventKit, and Swift-in-nix is its own project. Reminders.app and
Calendar.app are fully scriptable through `/usr/bin/osascript` — stable
system binaries, zero new dependencies (the mini's python env already
exists). The trade-offs, stated honestly:
- TCC becomes *Automation* grants ("python wants to control
  Reminders/Calendar") instead of EventKit grants. One interactive
  approval at the mini's screen. **Known operational cost:** the grant
  keys on the python binary's store path, so a `just update` that
  changes the python env re-prompts — post-update, tools hang until
  re-approved on screen (the brief then says "calendar unavailable",
  never stale — the designed failure mode). Documented in the phase doc.
- AppleScript is slower than EventKit (~1–3 s per query) — irrelevant at
  brief/chat volumes.

**`hosts/darwin/mini/apple-mcp/server.py`** — same shape as the vault
server (bearer ASGI wrapper, loopback :9103, ProcessType=Interactive):
- `list_reminders(list?, include_completed=False)` — due/overdue focus
- `create_reminder(title, due?, notes?)` → **"Hermes Review" list only**
- `complete_reminder(name)` — in Hermes Review only
- `list_events(days_ahead=1, calendar?)` — read every visible calendar
  (subscriptions included, labeled by calendar name)
- `create_event(title, start, end, notes?)` → **"Hermes Review"
  calendar only**
- NO delete, NO edits to non-Hermes-Review items, no attendees/
  recurrence/attachments — the AppleScript for those simply isn't in
  the file.

**Plumbing (all existing patterns):** second launchd user agent;
`tailscale serve --https=8322 → 127.0.0.1:9103`; new
`apple-mcp-token` in both secrets (same generate-unseen flow); egress
line `mini:8322`; `services.hermes-agent.mcpServers.apple` with the
five-tool include and `${APPLE_MCP_TOKEN}` header.

**Behaviors:** replace the daily-note cron's prompt with the full
morning brief (daily note + reminders due + today's events + one-line
WAN status via the unifi tool; each section says "unavailable" on
bridge failure). Telegram "remind me to X" flows naturally once the
tool exists.

## Your checklist
1. In Reminders on any device: create a list named **Hermes Review**.
   In Calendar: create a calendar named **Hermes Review** (iCloud).
2. One-time TCC approvals at the mini's screen (or Screen Sharing) when
   I trigger them — two dialogs: python→Reminders, python→Calendar.
3. The governance question, only if/when you want [WORK] in the brief:
   explicit yes/no on work-calendar data through Anthropic + Telegram.
   Building proceeds personal-only either way.

## Acceptance
- Telegram reminder → iPhone within seconds, in Hermes Review with due
  date; morning brief shows real calendar+reminders; jail: create
  outside Hermes Review refused at tool layer; no delete exists;
  bridge unreachable → brief says unavailable; reboot recovery = agent
  resumes at login (documented mini trade-off); audit digests only;
  phase-4 doc with the TCC re-grant runbook.

## Files
| File | Action |
|---|---|
| `hosts/darwin/mini/apple-mcp/server.py` | new |
| `hosts/darwin/mini/default.nix` | edit (second agent + sops secret) |
| `secrets/mini.yaml` + `hermes-env` | new `apple-mcp-token` (I generate unseen, as before) |
| `hosts/nixos/nixos-infra/hermes-egress.nix` | edit (mini:8322) |
| `hosts/nixos/nixos-infra/apple.nix` | new (hermes wiring) |
| daily-note cron | replaced by morning-brief prompt (CLI) |
| `docs/hermes/phase-4.md`, `runtime.md` | close-out |

Deploys: mini needs one `just` from you (new agent) + the TCC clicks;
VM via `just deploy`. Disable: remove `./apple.nix` import / bootout the
agent / `serve --https=8322 off`; revoke: rotate `apple-mcp-token`.

**Awaiting your "go" (+ the Hermes Review list/calendar created).**
