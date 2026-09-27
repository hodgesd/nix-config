# hn-summaries — shared Hacker News discussion summaries

Built 2026-09-26. Module `hosts/nixos/nixos-infra/hn-summaries.nix`, app
`hosts/nixos/nixos-infra/hn-summaries/server.py`.

## What it is

The daily_news SwiftBar plugin (`hodgesd/swiftbar_plugins`,
`daily_news_uv.2h.py`) shows a discussion summary as the tooltip of every
Hacker News row. Before this service each Mac resolved those on its own —
local cache → HN Companion → a paid OpenRouter call through the `llm` CLI —
so mbp, air and mini each paid for the same story and each needed `llm`,
`llm-openrouter` and a key configured by hand.

Now one native service on nixos-infra owns the cache (SQLite) and the paid
call. The Macs ask it first with one batched request; anything it returns
lands in the Mac's local cache too. A Mac off the tailnet, or the service
being down, falls back to the old chain unchanged. Topic sections ask with
`llm=0`, so niche stories only ever get a summary the front page already
paid for.

The thread flattening, prompt and output contract ("one overview paragraph,
a blank line, 3-5 `• Theme — one sentence` bullets") are the plugin's own
functions copied verbatim, so a tooltip looks the same whichever side made
it. Keep them in sync — check with:

```bash
diff <(python3 - <<'PY'
import ast,sys
src=open("hosts/nixos/nixos-infra/hn-summaries/server.py").read(); t=ast.parse(src)
for n in t.body:
    if isinstance(n,ast.FunctionDef) and n.name in ("flatten_hn_thread","sanitize_llm_summary","condense_hncompanion_summary","_comment_text"): print(ast.get_source_segment(src,n))
PY
) <(python3 - <<'PY'
import ast,sys
src=open("/Users/hodgesd/PycharmProjects/swiftbar_plugins/daily_news_uv.2h.py").read(); t=ast.parse(src)
for n in t.body:
    if isinstance(n,ast.FunctionDef) and n.name in ("flatten_hn_thread","sanitize_llm_summary","condense_hncompanion_summary","_comment_text"): print(ast.get_source_segment(src,n))
PY
) && echo "in sync"
```

## API

Tailnet-only, plain HTTP, read-only: nothing here mutates configuration.

| Request | Answer |
|---|---|
| `GET /healthz` | `{"ok": true, "cached": N, "llm_calls_today": N, "daily_cap": 60, "llm_enabled": true, "model": "…"}` |
| `GET /hn?ids=1,2,3&llm=1` | `{"<id>": {"summary", "source", "model", "fetched_at"}}`, missing ids omitted. `source` is `cache` (SQLite hit), `companion` or `llm`. At most 50 ids, digits only; else 400. |
| `GET /hn?ids=…&llm=0` | Same, but never spends: SQLite and HN Companion only. The topic sections use this. |

Base URL from a Mac: `http://nixos-infra-1:8090` (the VM's MagicDNS name is
`nixos-infra-1`; bare `nixos-infra` does not resolve).

Pipeline per id: SQLite → miss marker (6 h) → HN Companion (free) → Algolia
`items/{id}` thread text → OpenRouter chat completion. A failed paid call
leaves a miss marker and never a summary; an auth/credit/rate-limit answer
pauses the paid path for 10 minutes and leaves no marker.

## Spend controls (settings in `hn-summaries.nix`)

- **One dedicated OpenRouter key** (`hn-summaries-env`), credit-limited at
  OpenRouter — the hard ceiling that survives any bug here.
- **Daily cap** `dailyLlmCap = 60` paid calls per UTC day, warmer included;
  then cache + Companion only, one journal line when it trips. In-flight
  calls count, so a burst cannot overshoot.
- **Single-flight per id**: simultaneous requests from three Macs (or the
  warmer) make one call. Three paid calls in flight at most.
- **Per-call timeout** 30 s, **input budget** 80 000 chars (~20k tokens),
  **max_tokens** 4096 (also keeps OpenRouter's per-call credit hold small).
- **Ledger:** every paid call logs
  `llm id=… model=… prompt_tokens=… completion_tokens=… reasoning_tokens=… cost_usd=… elapsed=…`
  and the same row goes into the `llm_calls` table. Measured 2026-09-26 with
  gpt-5-mini at minimal effort: $0.0008 for a 6k-char thread, $0.0048 for an
  80k-char one.

```bash
ssh root@100.98.163.36 journalctl -u hn-summaries --since today | grep 'llm id='
ssh root@100.98.163.36 journalctl -u hn-summaries --since today | grep 'llm id=' | grep -o 'cost_usd=[0-9.]*' | cut -d= -f2 | paste -sd+ | bc
```

## Warmer

`hn-summaries-warm.timer` runs every 30 minutes (`*:0/30`, 3 min jitter,
persistent): fetch the Algolia front page (15 ids), call the service on
loopback with `llm=1`, print `{id: source}`. It goes through the service so
the same locks and cap apply. `journalctl -u hn-summaries-warm` shows what
each run found.

## Verify

```bash
curl -s http://nixos-infra-1:8090/healthz                       # ok:true, counters
curl -s 'http://nixos-infra-1:8090/hn?ids=49854416&llm=1' | jq   # a summary with source
ssh root@100.98.163.36 systemctl list-timers hn-summaries-warm    # next/last run
ssh root@100.98.163.36 journalctl -u hn-summaries -n 30           # request + llm lines
```

Gatus: group `nixos-infra`, endpoint `hn-summaries` (polls `/healthz`
through the tailnet name, condition `[BODY].ok == true`), alerts to the
usual ntfy topic.

## Disable

Remove `./hn-summaries.nix` from the imports in
`hosts/nixos/nixos-infra/default.nix` and `just deploy`. The plugin falls
back automatically (local cache → HN Companion → local `llm`). Afterwards:
`rm -rf /var/lib/private/hn-summaries` on the VM, revoke the `hn-summaries`
key at OpenRouter, delete the `hn-summaries-env` entry with
`sops secrets/nixos-infra.yaml`, and drop the Gatus endpoint.

Client side, the plugin's `~/.config/swiftbar-plugins/daily_news.json` can
carry `"summary_service_url"` to point elsewhere, and `"summaries": false`
turns the Mac's own paid path off once the service is trusted.

## Credential inventory (names and scopes only)

| Name | Where | Scope |
|---|---|---|
| `hn-summaries-env` → `OPENROUTER_API_KEY` | sops `secrets/nixos-infra.yaml`, decrypted to `/run/secrets/hn-summaries-env`, read by systemd as root, process runs as a DynamicUser | OpenRouter key created for this service only, credit-limited at OpenRouter. Chat completions only; no account or billing scope exists on OpenRouter keys. |

Nothing else: Algolia and HN Companion are unauthenticated public APIs, and
the service accepts no credentials from clients.

## Manual test script (5 items)

1. From a Mac: `curl -s http://nixos-infra-1:8090/healthz` → `"ok": true`
   and `"llm_enabled": true`. From a phone on LTE (off the tailnet): the same
   URL must not connect.
2. `curl -s 'http://nixos-infra-1:8090/hn?ids=<a current front-page id>&llm=1' | jq .`
   from **two** Macs within a minute. `journalctl -u hn-summaries | grep 'llm id=<id>'`
   on the VM shows exactly one line; the second Mac's answer says
   `"source": "cache"`.
3. `curl -s 'http://nixos-infra-1:8090/hn?ids=<an obscure old story id>&llm=0'`
   → `{}` and no new `llm` line: `llm=0` never spends.
4. `systemctl start hn-summaries-warm && journalctl -u hn-summaries-warm -n 3`
   on the VM → one JSON object mapping 15 ids to `cache`/`companion`/`llm`.
5. Open Gatus (https://status.jaguar-duckbill.ts.net): `nixos-infra /
   hn-summaries` is green. Then on a Mac, hover a Hacker News row in the
   daily_news dropdown after a refresh: the tooltip is the overview plus
   bullets, identical in shape to a Companion one.
