# Telegraph-Hermes Integration Plan
### Personal AI agent infrastructure — security-first, phased, independently adoptable

**Owner:** Derrick · **Infra:** nixos-infra (Proxmox), nix-darwin Mac(s), Tailscale tailnet, UNAS Pro 8
**Version:** 1.1 · August 2026 (v1.1 changelog at end — incorporates external security review, 2026-08-30)

---

## 1. Target Architecture

```
                        ┌─────────────────────────────────────────┐
                        │                TAILNET                   │
                        │            (WireGuard mesh)              │
                        │                                          │
 ┌──────────┐  Telegram │  ┌────────────────────────────────────┐ │
 │  iPhone  │───────────┼─▶│  nixos-infra VM: hermes             │ │
 │ Telegram │◀──────────┼──│  ┌──────────────────────────────┐  │ │
 └──────────┘   push    │  │  │ Telegraph (Telegram gateway) │  │ │
                        │  │  └──────────────┬───────────────┘  │ │
                        │  │  ┌──────────────▼───────────────┐  │ │
                        │  │  │ Hermes agent core (LLM loop) │  │ │
                        │  │  │  + policy.md (agent rules)   │  │ │
                        │  │  │  + audit log (every call)    │  │ │
                        │  │  └──┬────┬────┬────┬────┬───────┘  │ │
                        │  │     │    │    │    │    │           │ │
                        │  │   MCP  MCP  MCP  MCP  files        │ │
                        │  │     │    │    │    │    │           │ │
                        │  └─────┼────┼────┼────┼────┼──────────┘ │
                        │        │    │    │    │    │            │
                        │        ▼    ▼    ▼    │    ▼            │
                        │   Fastmail UniFi Graph│  Obsidian vault │
                        │   (JMAP)  (local (MS  │  (synced copy   │
                        │           API)  cloud)│   on NAS/VM)    │
                        │                       │                 │
                        │        HTTPS over tailnet only          │
                        │                       │                 │
                        │  ┌────────────────────▼──────────────┐  │
                        │  │  Mac (nix-darwin)                 │  │
                        │  │  apple-bridge MCP (EventKit)      │  │
                        │  │  → Reminders, Apple Calendar,     │  │
                        │  │    (Outlook via Internet Accounts)│  │
                        │  │  bound to Tailscale IP only       │  │
                        │  └───────────────────────────────────┘  │
                        └─────────────────────────────────────────┘
```

**Runtime (identified):** Hermes is NousResearch's open-source `hermes-agent` — Python core, native MCP integration, built-in cron scheduler with Telegram delivery, and numeric-user-ID allowlisting on the Telegram gateway ("Telegraph" = the Telegram surface). Three consequences: our MCP servers plug into its native config; scheduled briefs/digests use its cron rather than custom timers; and the policy allowlist maps to real enforcement (`TELEGRAM_ALLOWED_USERS`). One critical addition to the security model: hermes-agent ships terminal-execution backends — **the agent has a shell.** See §3.1 principle 8.

Key placement decisions:

- **Hermes + network-API integrations live on nixos-infra.** Fastmail (JMAP), UniFi (local Network API on the gateway), and Microsoft Graph are plain HTTPS APIs — no reason to involve the Mac.
- **The Mac runs exactly one thing:** a thin MCP bridge for EventKit (Reminders + Calendar). It is the only integration that architecturally requires macOS. It binds to the Tailscale interface, requires a bearer token, and is unreachable from the LAN or internet.
- **Obsidian is files, not an app integration — and iCloud stays the only sync engine.** The vault lives in Obsidian's iCloud folder; layering Syncthing (or any second sync engine) onto an iCloud-synced folder invites eviction-stub corruption and conflict storms. Instead, a small path-jailed filesystem MCP server runs on the Mac mini (which holds a live local copy via iCloud, pinned always-downloaded) and Hermes reaches it over the tailnet — same plumbing as the EventKit bridge.

---

## 2. How the Technologies Work (high level)

**MCP (Model Context Protocol).** A client (Hermes) connects to servers (one per integration) over stdio or HTTP. Each server publishes a typed tool catalog — name, parameters, description. The LLM decides *which* tool to call; the server *executes* it and returns results. The security property that matters: **the tool catalog is the ceiling.** A server with no delete tool cannot delete, regardless of what the model is tricked into wanting. You shape risk by shaping the catalog.

**JMAP (Fastmail).** JSON-over-HTTPS successor to IMAP, designed by Fastmail. Batched requests, efficient sync, single protocol for mail/calendar/contacts. Auth is a bearer API token you mint in Settings → Privacy & Security → Integrations — scoped, named, individually revocable. No password ever leaves your password manager.

**EventKit + TCC (macOS).** EventKit is Apple's native framework for Reminders/Calendar data. TCC (Transparency, Consent, and Control) is the macOS permission system: the first EventKit call from a binary triggers a user-facing grant prompt, recorded per-binary in System Settings → Privacy & Security. Gotcha: in a headless/launchd context the prompt can't render and the call hangs — so you grant interactively once, then the daemon runs cleanly.

**Microsoft Graph.** OAuth 2.0 against Entra ID. You register an app, request granular scopes (`Calendars.Read` is a different grant than `Calendars.ReadWrite` than `Mail.Send`), and the tenant (Enterprise IT) consents. Tokens are short-lived; refresh tokens are revocable tenant-side. Because this is your **work** tenant, treat it as the highest-sensitivity, last-implemented, read-only-longest integration.

**UniFi Network API.** Official API-key auth (Settings → Control Plane → Integrations on your console). The local gateway API supports reads and (with the right servers) previewed writes; Ubiquiti's cloud Site Manager API is read-oriented. Keys inherit the role of the account that made them — make a dedicated read-only admin user for the agent's key.

**Tailscale.** WireGuard mesh where every node has a stable identity and 100.x address. ACLs (declarative, in your admin console or GitOps) define which tagged nodes may reach which ports. `tailscale serve` gives you real HTTPS certs on tailnet-only services — your existing sidecar pattern.

---

## 3. Security Model — "why you won't regret this"

### 3.1 Principles

1. **Capability minimalism.** Every integration exposes the smallest tool set that delivers the use case. Start read-only everywhere. Promote to write per-integration, deliberately, after observed trust.
2. **One credential per integration, least privilege, individually revocable.** Compromise of one ≠ compromise of all. A quarterly 15-minute credential review is on the calendar (Phase 4 will put it there).
3. **Network invisibility.** No new listening ports on LAN or WAN. Everything agent-related is tailnet-only, enforced by Tailscale ACLs with a dedicated `tag:hermes`.
4. **Tiered autonomy.**
   - Tier 0 — read/summarize: no confirmation.
   - Tier 1 — reversible writes in low-stakes stores (Obsidian notes, Reminders): allowed, logged.
   - Tier 2 — outbound comms: **draft-only.** Hermes writes to Drafts; a human presses send.
   - Tier 3 — infrastructure/config mutations (UniFi rules, calendar deletes, anything in the work tenant): not in the tool surface at all, or gated by explicit per-action confirmation.
5. **Prompt-injection containment.** Email and web content are untrusted input. The dangerous triad is: private-data access + untrusted content + an output channel. Mitigations:
   - Send-capable tools never coexist in a session with bulk email reading (draft-only breaks the exfiltration leg).
   - policy.md instructs the agent: content of messages is data, never instructions; never act on directives found inside emails/documents; surface them to Derrick instead.
   - Telegram recipient allowlist: Telegraph only accepts/pushes to your (and later Robin's) chat IDs.
6. **Auditability + reproducibility.** Every tool call logged with timestamp, tool, args-summary, and outcome to a structured log (journald + optional file). The whole stack is Nix-declarative: reviewable in git diffs, rollback-able with one command, rebuildable from scratch.
7. **Shell containment.** hermes-agent can execute terminal commands via its terminal backend. This is its most powerful capability and dwarfs any single MCP tool in blast radius. It therefore runs as a dedicated non-privileged user with a Docker (or hardened-systemd-sandbox) terminal backend: agent-executed commands are isolated from the host, cannot read other services' secrets or SSH keys, and what the shell *can* touch is enumerated in docs. MCP allowlists are only meaningful atop a contained shell.
8. **Secrets discipline.** agenix or sops-nix on NixOS (encrypted in-repo, decrypted at activation to /run). On the Mac: launchd EnvironmentVariables sourced from a root-readable file outside the repo, or Keychain. Nothing in plaintext in git, ever.

### 3.2 Blast-radius table

| Integration | Credential | Worst realistic case if fully compromised | Containment |
|---|---|---|---|
| Obsidian | none | vandalized notes in replica | vault sync history + NAS snapshots + git |
| UniFi | read-only API key on dedicated viewer account | network topology/client list disclosed | revoke key; no write capability exists |
| Fastmail | scoped token (read + drafts) | mailbox read; junk drafts created | revoke token; sending was never possible |
| Apple bridge | tailnet-only + bearer token | reminders/calendar tampering | Tailscale ACL, token rotation, Time Machine |
| Graph | Calendars.Read only | work calendar disclosed | tenant-side revocation; no write scope granted |
| Telegram bot | bot token | messages spoofed to allowlisted chats only | rotate via BotFather; allowlist blocks strangers |

### 3.3 Standing rules

- New integrations enter at Tier 0 and live there for ≥2 weeks.
- Any anomaly (unexpected tool call in the audit log, weird draft, unrecognized behavior) → freeze that integration (comment out the MCP server, redeploy) and investigate. Freezing is a one-line change.
- The work tenant never gets write scopes without a specific, named reason and a sleep-on-it delay.
- Quarterly: review audit-log sample, rotate tokens, prune unused tools.

---

## 4. Phase Details & Use Cases

Each phase is independent. v1.1 recommended order: **0.5 → 2 (lowest data
sensitivity first) → 1 → 4 → 3a → 3b**, but 1/2/3a still run in any order
after 0.5. Phase 5 can be skipped entirely if the EventKit fallback
(Outlook account in macOS Internet Accounts, read via Phase 4) is good
enough. Phase 6: start with the currency sentinel, homelab sentinel, and
gym log; each riskier sub-block (Tesla, Shortcuts/HomeKit, Robin's ops)
waits for its own mini threat model.

### Phase 0 — Foundation (prerequisite for all)
**Build:** secrets management (agenix/sops-nix), `tag:hermes` + ACLs in Tailscale, structured audit logging middleware for all MCP traffic, `policy.md` (agent constitution: tiers, injection rules, tone, allowlists), NixOS module skeleton for declaring MCP servers.
**Payoff:** invisible until something goes wrong — then it's everything.
**Effort:** one evening.
**Status: DONE 2026-08-29** — see `docs/hermes/phase-0.md`.

### Phase 0.5 — Containment gate (before ANY data integration; three hard gates)
*Added in v1.1; hardened in v1.1.1 after the second review round. The
v1.1 draft deferred the terminal decision to Phase 3a/1 on the premise
that no untrusted content flows yet — that premise was false: the
deployed Telegram preset already includes `web` and `browser`, so the
agent can already pull arbitrary web content into a session that also has
a shell, `file` tools that can read its own dotenv (including the bot
token), and unrestricted egress. The sender allowlist authenticates who
messaged, not what the content does. All three gates are therefore
immediate.*

**Gate 1 — split the surfaces.** The Telegram profile becomes minimal:
messaging, todo, and (judgment call at implementation) vision/tts —
**no terminal, no web, no browser, no file, no skills, no cronjob**.
Operator/terminal utility moves to the surface that already exists for
it: the `cli` platform (the `hermes` CLI on the VM over SSH keeps the
full preset) — no second bot needed. Scheduled briefs become
deployment-declared, not chat-editable. The utility loss on the phone is
real (no ad-hoc shell or web lookups from Telegram) and temporary in
spirit: the integrations ARE the intended utility, delivered through
allowlisted MCP tools as phases land.

**Gate 2 — real egress policy, not just a bridge.** Remove
`--network=host`. But a Docker bridge network still masquerades all
outbound by default — the bridge is step one, enforcement is separate:
per-container firewall rules (DOCKER-USER chain / nftables matching the
container's fixed bridge IP) or an egress proxy, allowing only DNS,
Telegram, Anthropic, and explicitly approved integration endpoints
(domain-based allowlisting favors the proxy approach since API IPs
rotate). VM-wide default-deny remains wrong for this shared-duty VM.
Accepted limitation: while hermes shares the VM's Tailscale identity,
tailnet grants cannot distinguish it from the VM's other services — if
that distinction ever matters, hermes gets its own Tailscale sidecar or
its own small VM/node; until then, dst-side auth carries that weight.

**Gate 3 — config genuinely immutable to the agent.** Confirmed bypass,
not a hypothesis: `config.yaml` is owned by the agent's own user, the
activation merge preserves agent-added keys (Nix keys win, new keys
survive), no `mcp_servers` key is Nix-declared, and the agent can force
its own restart (crash + `Restart=always`). So a compromised agent could
persist its own MCP server or toolset override across deploys. Fix
mechanism: read-only bind-mounts over the in-container paths for
`config.yaml` and workspace `AGENTS.md` (`container.extraVolumes`
`...:ro`), leaving the agent a narrow writable state (sessions, logs,
memory — SOUL.md/MEMORY.md stay agent-managed by design; note that the
identity slot is therefore agent-writable, which is why policy lives in
the ro AGENTS.md). Verify the merge/inode behavior across activation.

**Validation battery:** unauthorized Telegram user ignored; egress to a
non-allowlisted host fails from inside the container while long-polling
works; agent-written config.yaml edit does NOT survive/load (gate 3
proof); revoked secret aborts activation cleanly; global kill switch +
reboot recovery; audit-log redaction spot-check.
**Payoff:** prompt-injection blast radius drops from "anything the VM
can reach, persistently" to "one session's conversation".
**Effort:** a weekend, honestly — the egress enforcement and its test
window are the bulk.

### Phase 1 — Obsidian, files-first
**Build:** *(v1.1: the v1.0 Syncthing-replica idea is dead — see the §1
placement decision: iCloud stays the ONLY sync engine.)* A small MCP
server on the Mac mini (which holds the live iCloud copy, pinned
always-downloaded), **jailed to the vault path**, exposing
purpose-shaped tools — `append_inbox`, `create_daily_note`, narrowly
scoped reads/search — not a generic filesystem surface. Templates for
daily notes / GTD inbox / debriefs matching your PARA structure. Backup:
one-way, versioned export to the UNAS, written by a job the agent has no
access to.
**Guardrails:** path jail at server-config AND process layer; deny-lists
for `.obsidian/`, `.git/`, dotfiles, symlinks, binaries; no delete, no
mass edits, no arbitrary overwrite (append-style patterns make iCloud
collisions rare and conflict-copy-recoverable); NAS snapshots as the
undo button. Prerequisite: pin the voice-transcription provider before
the voice-capture use case goes live (see §5).
**Use cases:**
- Telegram voice/text → filed GTD inbox note with suggested PARA location and tags.
- 05:30 daily note auto-created: calendar summary, due tasks, weather, carried-over items.
- Sunday weekly-review packet: everything created/modified this week, open loops, stalled projects.
- "Draft a flight-debrief note for tomorrow's KTEB trip" → templated note ready in Projects.
- Meeting prep: "brief me for the VP staffing meeting" → assembles relevant notes into one prep doc.

### Phase 2 — UniFi, read-only
**Build:** dedicated read-only "hermes-viewer" admin account on the console → API key from that account; deploy a read-only-capable UniFi MCP server (e.g., sirkirby's unifi-network-mcp in read-only permission mode, or a lean read-only server) as a NixOS service; scheduled WAN-health watcher.
**Guardrails:** the key *cannot* write because the account can't. Even if you later adopt a fuller server, its preview-before-confirm gates mutations.
**Use cases:**
- **Spectrum WAN-flap forensics:** timestamped outage log + weekly summary → ammunition for support calls.
- "New device joined: unknown MAC on IoT VLAN at 2:14 AM" → Telegram alert.
- On-demand: "why is the wifi slow in the basement gym?" → AP client load, channel utilization, RSSI.
- Monthly ISP report: uptime %, latency percentiles, flap count.

### Phase 3 — Fastmail, split in two (v1.1)
*The v1.0 "token scoped to read + drafts" assumed scoping granularity
Fastmail doesn't offer: read-only tokens can't create drafts, and the
write-capable Mail scope can modify and permanently delete. So drafts
cannot be enforced at the credential layer — which changes the design.*

**Phase 3a — read-only triage.** Read-only API token; JMAP MCP server
with read/search/list tools only; triage prompt templates. This is the
first untrusted-content integration — the Phase 0.5 terminal decision
gates it, and policy.md's injection rules apply hardest here.
**Phase 3b — draft broker (optional; only if 3a earns it).** A separate,
tiny, purpose-built service exposing exactly `create_draft` — not a
general JMAP server with tools disabled. It alone holds the read-write
token (its own sops secret, its own service identity); its code is the
enforcement boundary, so it stays small enough to actually review.
Verify Fastmail's current scope granularity at implementation in case
this has improved.
**Guardrails:** Tier 2 — drafts only, structurally. Metadata-first tools
preferred (subjects/senders before bodies) to limit exposure.
**Use cases:**
- 06:00 Telegram triage: "14 new; 2 need you: USAA umbrella docs, Lindenwood billing for Cameryn. Rest is noise."
- "Draft a reply to the Prestige Pools email asking for the updated HELOC-friendly payment schedule" → waiting in Drafts.
- Receipt harvesting: weekly extraction of order/receipt emails into a summary note (feeds Actual Budget habit).
- "Anything from Harvey Watt or UNUM in the last 30 days?" — instant recall without inbox spelunking.

### Phase 4 — Apple bridge (Reminders + Calendar)
**Build:** on the Mac via nix-darwin: an EventKit MCP server (Swift or Node; e.g., apple-events-mcp style with streamable HTTP + API-key auth) as a launchd agent, **bound to loopback and exposed only through `tailscale serve`** (v1.1 — Tailscale's own recommendation when relying on Serve's identity/grant enforcement, and the house sidecar pattern anyway); one-time interactive TCC grant; Hermes points at it over the tailnet.
**Guardrails:** tailnet-only + bearer token; tool surface = create/read/update reminders, read/create calendar events; **no delete tools** in v1. v1.1 additions: writes land only in a dedicated **"Hermes Review"** calendar and Reminders list until observed trust promotes them — no attendees, recurrence, attachments, or edits to non-allowlisted calendars; note EventKit's grant model (reads need full access; write-only exists for event creation) when picking the server; and when the bridge is unreachable the brief must **say "calendar/vault unavailable" — never silently degrade to stale data**. Hardware (final): the existing daily-use Mac mini — shared work/play machine, screen attached. FileVault stays on, no auto-login; system sleep prevented while display sleep allowed; bridge runs as a launchd agent in Derrick's session, so services resume at login after any reboot (brief downtime accepted). No new hardware purchase.
**Use cases:**
- "Remind me to stow the gear pin blocks writeup Friday" from Telegram → correct Reminders list, due date set.
- Morning brief merges due-today/overdue Reminders with the day's calendar into one Telegram message.
- Email→task: "turn that UNUM email into a task with a link in the notes."
- Travel-day scaffolding: show time, drive-to-SUS block, family events that conflict.
- Work calendar (solved): Derrick already subscribes to the published work Outlook calendar in Apple Calendar. If the subscription's location is iCloud, the mini sees it automatically and the EventKit bridge reads it — labeled [WORK], read-only by protocol and by tool surface. Only verification needed: subscription location (iCloud vs On My Mac) and refresh interval. No Internet Accounts, no OWA changes, no IT contact, and Phase 5 stays permanently shelved barring future need.

### Phase 5 — Outlook calendar via Microsoft Graph (SKIPPED — shelf contingency)
*Decision: not implementing. Work calendar rides Phase 4 (Internet Accounts, ICS fallback second). This phase exists only if both Phase-4 paths are tenant-blocked and the brief proves worth an IT conversation.*
*v1.1 governance note (applies to the Phase-4 ride-along too): the ICS
subscription already reaches personal devices today — the marginal step
this plan adds is **LLM processing and Telegram delivery** of work
calendar data. That is an employer-policy question, not a technical one;
answer it before wiring the [WORK] section of the brief, and prefer a
busy/free-only projection if the answer is a qualified yes.*
**Build:** Entra app registration (delegated `Calendars.Read`), tenant admin consent (talk to Enterprise IT — as Chief Pilot you have the standing to ask; frame it as "read-only calendar access for a personal scheduling assistant"), device-code or auth-code flow, Graph MCP server on nixos-infra.
**Guardrails:** read-only scope, tenant-revocable, last-implemented, longest-observed. If IT says no: use the Phase 4 EventKit fallback and lose nothing but API elegance.
**Use cases:**
- True unified brief: trips, board travel, pilot meetings + family calendar, conflicts flagged.
- "What's my duty picture next week vs. Robin's delivery days?"
- Recurrent-training deconfliction against personal commitments.

### Phase 6 — Creative layer (pick à la carte)
- **Aviation wx brief (free public APIs, zero credentials):** aviationweather.gov METAR/TAF/PIREPs + FAA NOTAM API. Morning brief computes KSUS crosswind components against the GVII 40-kt AFM limit and flags trends. Trip-day variant pulls destination + alternate.
- **Actual Budget MCP:** you self-host it; community servers exist. "Gym-build spend this month?" "Are we on plan for the pool HELOC payment?" Pairs with Phase 3 receipts.
- **GitHub MCP:** canigo + nfz_watchlist issue/PR triage; "what did I leave half-finished last weekend?"
- **Tesla/Powerwall (Teslemetry or Fleet API):** daily solar production vs. consumption, Powerwall reserve before storm days, "precondition the Y at 0645."
- **Robin's ops:** Uptime Kuma already watches her app; add order-digest pushes once the Card My Yard app ships. Nightly "tomorrow's signs" summary. *(v1.1: Robin gets a **separate bot/profile with its own toolset** — the allowlist and tool surface are global per bot, so a second allowlisted ID on Derrick's bot would inherit his entire capability set. Heavier to run, but the right shape; needs its own small threat model before building.)*
- **Tesla/Powerwall, properly tiered:** Tier 0 is entirely local/self-hosted — TeslaMate on the homelab logging both cars (drives, charging, battery health) with a read-only TeslaMate-DB MCP server for analytics, plus pypowerwall against the local Energy Gateway for solar/battery data on the LAN. No Fleet API, no cloud billing, no command capability exists. Vehicle commands (precondition, charge control) are a separate future decision: they require Fleet API signed-command infrastructure via a proxy service (Teslemetry / MyTeslaMate) or self-hosted command proxy, cost per-use, carry retry double-execution risk, and would enter at Tier 3 confirm-gated.
- **Gym log:** "log: belt squat 4x10 @90, incline walk 30min" → structured Obsidian note; monthly trend vs. DEXA body-comp goal. (Deliberately *not* wiring calorie targets through the agent — logging and trends only.)
- **Shortcuts bridge (6G):** one allowlisted `run_shortcut` tool on the mini turns everything with a Shortcuts action into agent-reachable capability behind a human-curated gate — HomeKit scenes, Focus modes, HomePod intercom. The allowlist IS the security model: Hermes can only fire shortcuts Derrick pre-built and pre-approved.
- **Homelab sentinel:** Hermes reads Uptime Kuma status and journald excerpts; "anything unhealthy?" from the couch.

---

### Phase 6 idea backlog (not yet work orders)
Captured for later triage; each would follow the same read-only-first, allowlist-gated pattern:
- **Currency & deadline sentinel (Chief Pilot):** a simple YAML/Markdown file in the vault holding personal dates — Class 1 medical due, flight review, recurrent, passport/KCM, LOA milestones — with Hermes warning at 60/30/7 days in the morning brief. Zero integration cost, outsized value; personal currency only (department records stay on department systems).
- **Family logistics feeds:** school/college academic-calendar ICS subscriptions folded into the brief the same way the work calendar is; "what's on the family radar this week."
- **Date-night finder (husband):** cross-calendar free-evening detection between Derrick's and Robin's calendars + a places_search suggestion — proposal delivered via Telegram, never auto-booked.
- **Sunday dinner / grocery flow (dad):** recipe pick → ingredient list appended to a shared Reminders grocery list both phones see.
- **Install-night routing (Robin's business):** once the Card My Yard app holds addresses, Hermes drafts an optimized yard-sign install route for the night's orders — pure computation on her own data.
- **Photos pipeline:** osxphotos on the mini for scoped exports (e.g., pull gym-build progress shots, or marketing photos for Robin) — export-only tooling, no library writes.
- **Backup sentinel:** `tmutil status` on the mini reported into the homelab health picture.
- **iMessage gateway (flagged, not recommended yet):** Hermes supports BlueBubbles/iMessage as a surface, which would let family interact without Telegram — but it means an agent touching the iMessage store, a high-sensitivity, ToS-gray integration. Revisit only after months of boring audit logs, if ever.

## 5. Operational Notes

- **Rollout cadence:** one phase per weekend max. Live with each before adding the next; the audit log tells you what the agent actually does vs. what you assumed.
- **Mac bridge hardware: resolved** — the existing daily-use mini hosts both small servers (EventKit bridge + vault filesystem). It's a shared work/play machine, not an appliance: prevent system sleep, keep FileVault on, accept that a reboot pauses the bridges until next login. If that downtime ever becomes annoying, a dedicated appliance is the upgrade path — not a prerequisite.
- **Backups (v1.1.1 — iCloud is sync, NOT backup):** vault via a one-way, versioned Mac-mini→UNAS backup job (agent-inaccessible; built in Phase 1) + NAS snapshots; Reminders/Calendar via iCloud + Time Machine to the UNAS; NixOS config in git. Encrypted off-site copy + quarterly restore test per §5 standing notes.
- **Kill switches:** per-integration = comment out the server + redeploy (minutes). Global = stop the hermes service. Credentials revocable service-side independently of your infra.
- **Credential separation (v1.1, standing rule):** the agent's own secret
  (`hermes-env`) never grows integration credentials. Every integration's
  credential lives with its own service identity (the mcp-server module's
  per-service `environmentFile`); Hermes holds at most a URL and bearer
  token per server.
- **NAS is for backups, not the agent (v1.1):** no writable NAS path is
  ever mounted into Hermes or its container. Vault/data backups are
  one-way, versioned, written by jobs the agent cannot touch; add an
  encrypted off-site copy and test restores quarterly.
- **Provider data flow (v1.1, corrected v1.1.1):** primary inference is
  Anthropic; the configured fallback (OpenRouter → DeepSeek open-weights)
  sees full session context when the primary fails. **Correction: routing
  through OpenRouter does not by itself guarantee US-only or
  fixed-provider inference** — OpenRouter routes across providers and has
  its own fallback behavior unless you set an explicit provider allowlist
  and disable provider fallbacks (account/request-level controls). Before
  any data phase (3a/1): either **fail closed to Anthropic** (drop the
  fallback — recommended for mail/vault sessions) or pin an explicit
  provider allowlist with data-collection/retention controls, and verify
  what hermes's `fallback_providers` actually passes through to
  OpenRouter. **Voice transcription has no pinned provider yet** — choose
  and document one before Phase 1's voice-capture use case goes live.
- **Tailscale policy (v1.1):** when applying the Phase-0 ACL draft, express
  it as **grants** (Tailscale's recommended syntax for new policy work)
  rather than legacy ACL entries — same substance.

---

## v1.1 changelog (2026-08-30)

Incorporates the external security review where it added signal (several
of its recommendations — digest-only audit logs, per-service identities,
account-layer write denial, deterministic UniFi collection, pinned
dependencies — were already built in Phase 0 or already specified here):
new Phase 0.5 containment gate (Telegram toolset narrowing, container off
host networking; terminal removal deliberately deferred to the first
untrusted-content phase); Phase 1 rewritten to match the iCloud-only
decision (v1.0's Syncthing-replica text contradicted §1) with
purpose-shaped tools and deny-lists; Phase 3 split into 3a/3b after the
Fastmail token-scope reality check; Phase 4 loopback+Serve binding,
"Hermes Review" write targets, unavailable-not-stale rule; Phase 5/work
calendar reframed as an employer-policy question; Robin moved to a
separate-profile design; operational notes above.

**v1.1.1 (same day, second review round):** the terminal-timing deferral
was withdrawn — the Telegram preset already carries `web`/`browser`/`file`
alongside the shell, so untrusted content already flows and the sender
allowlist does not make content safe. Phase 0.5 is now three immediate
hard gates: minimal Telegram surface (operator utility stays on the CLI
platform), real per-container egress enforcement (a Docker bridge alone
still masquerades all outbound), and agent-immutable config via ro
bind-mounts (the activation merge preserving agent-added keys is a
confirmed tool-ceiling bypass, not a test item). Also corrected: the
OpenRouter fallback needs an explicit provider allowlist or removal —
routing via OpenRouter guarantees neither US-only nor fixed-provider
inference; EventKit grant model treated as proof-of-concept with
calendar/list IDs enforced in the bridge; last stale Syncthing backup
reference replaced with the one-way mini→UNAS design.
