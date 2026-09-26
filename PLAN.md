# PLAN.md — hn-summaries: shared Hacker News discussion summaries on nixos-infra

Intended changes only. **Nothing is applied until you say "go".**

## What it unlocks

- **One paid call per story, not one per Mac.** Today mbp, air and mini each
  run `llm` against OpenRouter for the same front-page story and each keeps
  its own cache under `~/.cache/swiftbar_hn_summaries`. The VM summarises a
  story once, keeps it in SQLite, and every Mac reads it in one batched GET.
- **No per-Mac llm setup.** A Mac only needs the tailnet. `llm`,
  `llm-openrouter` and the key stop being a per-machine chore (the local
  path stays as a fallback and can be switched off once the service is live).
- **Topic sections get summaries too**, under a global spend cap: they ask
  with `llm=0`, so they only ever receive what the front page (or the
  warmer) already paid for.
- **Cache hits on refresh.** A 30-minute warmer summarises the current
  front page, so the 2-hourly SwiftBar refresh almost never waits on a model.

## Design

### Where it lives

- `hosts/nixos/nixos-infra/hn-summaries.nix` — imported from `default.nix`.
  Native systemd service + a warmer timer. Follows `easy-afd.nix` for the
  Python env and hardening set, `healthchecks.nix`/`gatus.nix` for sops +
  `DynamicUser` + `EnvironmentFile` + `restartUnits`, and the same bind and
  firewall stance as easy-afd/gatus.
- `hosts/nixos/nixos-infra/hn-summaries/server.py` — one file, ~400 lines,
  `aiohttp` (server + client), `beautifulsoup4`, stdlib `sqlite3`. No web
  framework. The thread flattening, char budget, prompt and the
  "overview paragraph + `• Theme — sentence` bullets" contract are ported
  **verbatim** from `daily_news_uv.2h.py` v2.2 (`flatten_hn_thread`,
  `SUMMARY_INSTRUCTION`, `sanitize_llm_summary`), so both paths render
  identically in the tooltip.
- `docs/HN-SUMMARIES.md` — what/API/spend controls/verify/disable/
  credential inventory/5-item manual test. One row added to the host
  services table in `docs/NIXOS-INFRA.md`.

### Network

- Binds `0.0.0.0:8090`. **Free port check:** the repo claims 8000 (easy-afd),
  8080 (gatus), 8321/8322 (hermes egress), 9101–9103 (MCP loopback);
  `ss -ltn` on the VM shows 22, 80, 443, 8000, 8080, 9101, 9102. 8090 is
  unused.
- Tailnet-only by the existing baseline: `nixos-common.nix` trusts
  `tailscale0` only, so the Macs reach `http://nixos-infra-1:8090` over
  WireGuard and the LAN gets nothing. **Never** added to `allowedTCPPorts`.
  Plain HTTP on purpose: machine-to-machine JSON over an encrypted tailnet;
  no `ts-*` sidecar (that pattern is for browser-facing TLS).
- **Name correction:** the VM's MagicDNS name is `nixos-infra-1`
  (`tailscale status`); bare `nixos-infra` does not resolve from a Mac
  (verified: `nixos-infra-1:8080` → 200, `nixos-infra:8080` → no route). The
  client default is therefore `http://nixos-infra-1:8090`.
- Tailnet ACL: nothing to apply if your policy is still default-allow (the
  Macs reach :8080 and :8000 today). If you have replaced it, the diff is one
  rule: `{"action": "accept", "src": ["autogroup:member"], "dst": ["tag:hermes:8090"]}`
  (the VM carries `tag:hermes`, and tags cover the whole node — see
  `docs/hermes/tailscale-acl.md`).

### API (read-only from the client's point of view; no endpoint mutates config)

- `GET /healthz` → `{"ok": true, "cached": N, "llm_calls_today": N, "daily_cap": 60}`.
  Gatus polls it (`[BODY].ok == true`); the counters make the cap visible.
- `GET /hn?ids=1,2,3&llm=1` → `{"<id>": {"summary", "source", "model", "fetched_at"}}`,
  missing ids omitted; `source` is `cache` (SQLite hit), `companion` or `llm`.
  `llm=0` means SQLite + HN Companion only — the topic sections use it.
  At most 50 ids per request (front page is 15); anything else → 400.

### Pipeline per id

SQLite `summaries` → `misses` (6 h TTL, skips the paid step only) →
HN Companion (`https://app.hncompanion.com/api/posts/{id}`, free, stored as
`companion`) → Algolia `items/{id}` thread text → OpenRouter
`POST /api/v1/chat/completions` over HTTPS with `Authorization: Bearer
$OPENROUTER_API_KEY`, `usage: {include: true}` so the reply carries cost.
No `llm` CLI on the VM. A failed paid call writes a miss marker, never a
summary.

### Nix settings (a commented `let` block, exported to the app as env vars,
matching how easy-afd/gatus keep config in Nix rather than custom options)

| Setting | Default | Why |
|---|---|---|
| `port` | 8090 | see Network |
| `model` | `openai/gpt-5-mini` | **deviation from the prompt** (which said `google/gemini-2.5-flash`, reasoning low): the 2026-09-26 bake-off found gpt-5-mini at minimal effort the most accurate and cheapest (2.5–4.4 s, ~$0.003/story); Gemini at reasoning low was 3× slower, 2× the cost and stalled past 60 s twice. You already switched the plugin to it. Say so in the go if you want Gemini instead. |
| `reasoningEffort` | `minimal` | sent as `reasoning: {effort}` |
| `maxTokens` | 4096 | caps runaway output and keeps OpenRouter's per-call credit hold small (it reserves the model's full output limit otherwise) |
| `dailyLlmCap` | 60 | paid calls per UTC day, warmer included; after that the service answers from cache + Companion only |
| `llmTimeout` | 30 s | per call |
| `threadCharBudget` | 80000 | ~20k input tokens |
| `missTtlHours` | 6 | matches the plugin |
| `warmEvery` | `*:0/30` | timer cadence |
| `warmTop` | 15 | Algolia `front_page` hits per warm run |

### Spend controls

- **Single-flight per id**: an `asyncio.Lock` per id inside the one
  process, so three Macs asking for the same fresh story trigger one call.
  Three paid calls in flight at most (semaphore), like the plugin.
- **Daily cap** counted from the `llm_calls` table, checked before each
  paid call; the warmer counts against the same number.
- **Per-call timeout** 30 s; **input budget** 80k chars.
- **Ledger:** every paid call logs one journal line
  `llm id=… model=… prompt_tokens=… completion_tokens=… reasoning_tokens=… cost_usd=…`
  and the same row goes into `llm_calls`, so `journalctl -u hn-summaries`
  is the cost ledger and `/healthz` shows today's count.

### Warmer

`hn-summaries-warm.service` (oneshot, `DynamicUser`, curl + jq) fetches
Algolia `search?tags=front_page&hitsPerPage=15` and calls
`http://127.0.0.1:8090/hn?ids=…&llm=1` — through the service, so the same
locks and cap apply. Timer every 30 min, `RandomizedDelaySec=3m`,
`Persistent=true`.

### Service unit

`DynamicUser`, `StateDirectory=hn-summaries` (SQLite at
`/var/lib/private/hn-summaries/hn-summaries.db`), the easy-afd hardening set
(`NoNewPrivileges`, `PrivateTmp`, `ProtectSystem=strict`, `ProtectHome`,
`ProtectKernelTunables`, `ProtectControlGroups`, `RestrictNamespaces`,
`LockPersonality`) plus `RestrictAddressFamilies=AF_INET AF_INET6`,
`Restart=always`, the same start-rate-limit fix easy-afd documents.
`EnvironmentFile` = sops `hn-summaries-env`; `restartUnits =
["hn-summaries.service"]` for the reason `default.nix` explains
(systemd doesn't notice EnvironmentFile content changes).

### Secret

New sops entry `hn-summaries-env` in `secrets/nixos-infra.yaml`, dotenv with
one line `OPENROUTER_API_KEY=…`. A **dedicated** key: not `hermes-env`'s,
not `workbench-env`'s, so its spend and revocation are independent.
The service refuses to start the paid path (and logs once) if the variable
is empty; cache + Companion keep working.

### Monitoring

One Gatus endpoint in `gatus.nix`, following the existing entries:
`(http "nixos-infra" "hn-summaries" "http://nixos-infra-1.jaguar-duckbill.ts.net:8090/healthz" ["[BODY].ok == true"])`,
alerting to the existing ntfy topic. No Homepage change (runtime state).

### Client change (`hodgesd/swiftbar_plugins`, `daily_news_uv.2h.py` → v2.3)

`resolve_hn_summaries` gains an `llm` flag. Order becomes: local cache →
**one batched GET to `summary_service_url`** (config key, default
`http://nixos-infra-1:8090`, 5 s timeout; `llm=1` from `fetch_hnt`, `llm=0`
from `fetch_topic_hn_items`) → results merged into the local cache →
HN Companion for what is left → local `llm` path (front page only, as today).
Any service failure (off the tailnet, service down, timeout) falls through
to today's behaviour unchanged. Docs note that `"summaries": false` turns the
local paid path off once the service is live.

## Files touched

- new `hosts/nixos/nixos-infra/hn-summaries.nix`, `hosts/nixos/nixos-infra/hn-summaries/server.py`, `docs/HN-SUMMARIES.md`
- edit `hosts/nixos/nixos-infra/default.nix` (import + sops entry), `hosts/nixos/nixos-infra/gatus.nix` (one endpoint), `docs/NIXOS-INFRA.md` (one table row)
- edit `secrets/nixos-infra.yaml` — **by you, via sops** (see checklist)
- swiftbar_plugins: `daily_news_uv.2h.py`; then `flake.lock` bump here

Commits, one logical change each: (1) service module + app + import + sops
entry, (2) warmer timer, (3) Gatus endpoint, (4) docs + drop PLAN.md,
then in swiftbar_plugins (5) client change, and here (6) lock bump.

## Your checklist (before I deploy — activation aborts if a declared secret is missing)

1. <https://openrouter.ai/settings/keys> → Create key. Name `hn-summaries`,
   credit limit **$5**, reset **monthly**. Copy it once; it is shown once.
2. `cd ~/nix-config && sops secrets/nixos-infra.yaml` and add a top-level entry:
   ```yaml
   hn-summaries-env: |
     OPENROUTER_API_KEY=<paste>
   ```
   Save; sops re-encrypts. Do not paste the key anywhere else (not here, not
   in the PR).
3. `secrets/nixos-infra.yaml` is already tracked, so nix sees the edit
   without `git add`. The **new** files (module, app, docs) must be
   `git add`ed before eval sees them — I do that; if you touch the tree
   yourself, remember it.
4. Tell me "go" (and "gemini" if you want the prompt's model instead of
   gpt-5-mini).

## After deploy, what you will see

1. `curl http://nixos-infra-1:8090/healthz` from this Mac.
2. The same 3 ids requested from two Macs; `journalctl -u hn-summaries`
   showing exactly one `llm id=…` line per id.
3. `systemctl list-timers hn-summaries-warm` and its last journal run.
4. Gatus `nixos-infra / hn-summaries` green.
5. Then the plugin change: push, `nix flake update swiftbar_plugins`, PR.

## Disable (one line)

Remove `./hn-summaries.nix` from the imports in
`hosts/nixos/nixos-infra/default.nix` and `just deploy`; the Macs fall back
to local cache → Companion → local `llm` automatically. State to delete
afterwards: `/var/lib/private/hn-summaries`. Revoke the `hn-summaries` key
at OpenRouter and delete the sops entry.

## Constraints honoured

No `mkForce` on activation scripts; `stateVersion` untouched; image pins
untouched; nixpkgs (26.05) only — `python3Packages.aiohttp` and
`beautifulsoup4` are both there, so no unstable needed; nothing new listens
on the LAN; secrets only through sops; every security-relevant line carries
a WHY comment; the service is reversible with the one line above.
