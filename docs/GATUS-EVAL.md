# Gatus vs Uptime Kuma — side-by-side trial

Started 2026-09-06. Gatus runs natively on `nixos-infra`
(`hosts/nixos/nixos-infra/gatus.nix`, https://gatus.jaguar-duckbill.ts.net);
Uptime Kuma is unchanged on the mini (`stacks/uptime/docker-compose.yml`,
https://uptime.jaguar-duckbill.ts.net). Gatus alerts to the ntfy topic
`gatus`; Kuma alerts to nothing (see the inventory).

## 1. Kuma inventory

Read from `~/srv/uptime/uptime-kuma/kuma.db` on the mini with
`sqlite3 -readonly` (Kuma 2.3.2, SQLite/WAL, schema v10). Push tokens were
seen and deliberately not recorded.

| Fact | Value |
|---|---|
| Monitors | 7 active |
| Notification providers | **0** (`notification` and `monitor_notification` empty) |
| Groups / parents / tags / status pages / proxies / docker hosts / maintenance | all 0 |
| Retention | 365 days |

| Name | Type | Target | Interval | Retries | Timeout | Accepted | Cert-expiry | Notes |
|---|---|---|---|---|---|---|---|---|
| actual-budget | http | https://budget.jaguar-duckbill.ts.net | 60 s | 0 | 48 s | 200-299 | off | |
| uptime-kuma | http | https://uptime.jaguar-duckbill.ts.net/dashboard | 60 s | 0 | 48 s | 200-299 | off | self-check |
| ntfy | http | http://ntfy.jaguar-duckbill.ts.net/dashboard | 60 s | 0 | 48 s | 200-299 | off | plain http |
| adguard | http | https://adguard.jaguar-duckbill.ts.net | 60 s | 0 | 48 s | 200-299 | off | 302→200 |
| librespeed | http | https://librespeed.jaguar-duckbill.ts.net | 60 s | 3 | default | 200-299 | **on** | |
| easy-afd-refresh | push | VM pushes after weekly data refresh | 8 d | 0 | — | — | off | `KUMA_REFRESH_PUSH_URL` |
| afd-healthz | push | VM pushes every 60 s after curling https://afd.hdgs.me/healthz | 180 s | 0 | — | — | off | `KUMA_AFD_PUSH_URL` |

Finding: Kuma is a dashboard, not an alerter. Every real alert in the
homelab comes from the ntfy timers on the VM (`kuma-watchdog.nix`,
`hermes.nix`, `unifi.nix`, `hermes-sentinel.nix`).

## 2. Mapping

Gatus 5.31.0 (nixos-25.11). Every endpoint carries `alerts: [{type: ntfy}]`
and inherits `default-alert` (failure-threshold 3, success-threshold 2,
send-on-resolved true). Kuma's per-monitor "retries" has no Gatus
equivalent; failure-threshold 3 is the stand-in. Groups are new (Kuma had
none) and follow the host being watched.

| Kuma | Gatus group/name | URL | Conditions | Result |
|---|---|---|---|---|
| actual-budget | nixos-infra/actual-budget | same | `[STATUS] >= 200`, `[STATUS] < 300` | 1:1 |
| ntfy | nixos-infra/ntfy | same | same | 1:1 (`/v1/health` + `[BODY].healthy == true` would be better; kept faithful) |
| adguard | nixos-infra/adguard | same | same | 1:1 |
| librespeed | nixos-infra/librespeed | same | same + `[CERTIFICATE_EXPIRATION] > 72h` | 1:1 |
| uptime-kuma | mini/uptime-kuma | same | same | 1:1; duplicates `kuma-watchdog.nix`, which could retire if Gatus wins |
| afd-healthz (push) | nixos-infra/easy-afd | https://afd.hdgs.me/healthz | `[STATUS] >= 200`, `< 300` | **converted** to a direct poll (Gatus is a tailnet peer on the host). Loses "VM is dead" detection; Kuma on the mini keeps that |
| easy-afd-refresh (push) | nixos-infra/easy-afd-refresh | external endpoint, `heartbeat.interval: 192h` | pushed by `easy-afd-refresh` with a bearer token | **converted** to a Gatus external endpoint |
| — | infra/mini | icmp://100.122.244.86 | `[CONNECTED] == true` | new |
| — | infra/nas | icmp://192.168.1.142 | `[CONNECTED] == true` | new |

Not replicable in Gatus (none used today): Docker container state, database
queries, MQTT, browser/screenshot, gRPC, RADIUS, GameDig, SNMP, Kafka.
Fallbacks: poll the app's own health URL, or keep those in Kuma.

## 3. How it is built

- `services.gatus` (upstream module): `DynamicUser`, `StateDirectory=gatus`
  (→ `/var/lib/private/gatus`, symlinked at `/var/lib/gatus`), SQLite at
  `/var/lib/gatus/data.db`, `EnvironmentFile=/run/secrets/gatus-env`.
- **ICMP:** the module sets `AmbientCapabilities=CAP_NET_RAW` and
  `CapabilityBoundingSet=CAP_NET_RAW`. Ping needs a raw socket, which is
  normally root-only; Linux "capabilities" split root into ~40 named
  powers and systemd hands the process exactly this one at start. Nothing
  else was needed. (The VM's `net.ipv4.ping_group_range` is also wide open,
  but Gatus uses privileged pings, so the capability is what matters.)
- **Secrets:** sops entry `gatus-env` (`GATUS_NTFY_TOPIC`,
  `GATUS_REFRESH_TOKEN`); Gatus expands `${VAR}` in its YAML at startup, so
  the store copy holds placeholders only. `easy-afd-env` gained
  `GATUS_REFRESH_PUSH_URL` + the same token for the refresh heartbeat.
- **HTTPS:** `ts-gatus` sidecar in `stacks/homelab/docker-compose.yml`
  (hostname `gatus`), proxying to `host.docker.internal:8080`. serve.json is
  nix-generated (`environment.etc."ts-gatus/serve.json"`) and bind-mounted
  read-only; the other sidecars' copies are hand-made on the host.
- **Firewall:** one `iptables` rule accepting TCP 8080 from Docker's
  private range (172.16.0.0/12). The baseline trusts only `tailscale0`, and
  the sidecar reaches the host over the compose bridge, not `tailscale0`.
  The LAN stays blocked.

## 4. Comparison

| Metric | Value |
|---|---|
| Kuma monitors | 7 |
| Replicated 1:1 in Gatus | 5 |
| Replicated with a different mechanism | 2 (push → direct poll; push → external-endpoint heartbeat) |
| Not replicable | 0 |
| New checks Kuma never had | 2 ICMP |
| Nix/YAML added | 200 lines: `gatus.nix` 164 (95 non-comment), compose 24, `easy-afd.nix` 11, `default.nix` 1 |

**Harder than expected**
- Exposing a *native* service through the sidecar pattern: needs a
  firewall rule plus `host.docker.internal`, neither of which
  Kuma-in-a-container ever needed.
- A new tailnet node means a new auth key; the one in `homelab-env` had
  been deleted ("API key does not exist"), so the sidecar could not
  register on the first deploy.
- Type strictness: `ntfy.priority` must be an integer; the README's
  `"default"` wording is misleading and a string crashes the service at
  start. `deploy-check` cannot catch this (it never runs the binary).
- No 1:1 for Kuma's per-monitor retries; thresholds are per alert.
- The rendered YAML can't be built on the Mac (x86_64-linux derivation), so
  it was checked via `nix eval --json …services.gatus.settings` instead.

**Easier than expected**
- ICMP: zero work, the module already grants the capability.
- SQLite storage is three lines; secrets slot straight into `${VAR}`.
- Groups, thresholds, send-on-resolved are plain YAML; Kuma's are
  per-monitor clicks in a UI.
- External endpoints with `heartbeat.interval` cover Kuma's push monitors,
  including the 8-day dead-man.
- The whole thing is one file plus a sidecar stanza, all in git.

## 5. Verification log (2026-09-06)

- `just deploy-check`: add secret `gatus-env`, modify `easy-afd-env`,
  reload `firewall`, restart `easy-afd` (its EnvironmentFile changed →
  `restartUnits`), start `compose-homelab` and `gatus`.
- First `just deploy` failed: `gatus.service` panicked on
  `alerting.ntfy.priority: "high"` — Gatus 5.31 wants an integer (1–5).
  Everything else activated. Fixed to `4`, redeployed clean.
- `systemctl show gatus`: `AmbientCapabilities=cap_net_raw`,
  `CapabilityBoundingSet=cap_net_raw`, `DynamicUser=yes`.
- Journal: "Validated 8 endpoints", "Validated 1 external endpoints"; all 8
  polled endpoints `success=true` on the first pass, ICMP included (mini
  2 ms, NAS 1 ms) — the capability works.
- Manual heartbeat POST with the token from `/run/secrets/easy-afd-env` →
  HTTP 200; `nixos-infra_easy-afd-refresh` shows `success=true`.
- Reachability: `http://100.98.163.36:8080` → 200 from the tailnet;
  `http://192.168.1.216:8080` from the LAN → no connection (firewall).
- `/var/lib/private/gatus/data.db` created (SQLite WAL).
- **Open:** `ts-gatus` is restart-looping with `invalid key: API key does
  not exist` — the `TS_AUTHKEY` in `homelab-env` has been deleted/expired.
  Until a new reusable tagged key is minted and put in `homelab-env`,
  https://gatus.jaguar-duckbill.ts.net does not exist; the dashboard is
  reachable over plain HTTP on the VM's tailnet IP only. The other six
  sidecars are unaffected (their identities live in their state dirs).
- **Not yet tested:** an end-to-end ntfy alert (needs the `gatus` topic
  subscribed first; then break one endpoint for 3 minutes).

## Disable

Remove `./gatus.nix` from `hosts/nixos/nixos-infra/default.nix` and the
`ts-gatus` stanza from `stacks/homelab/docker-compose.yml`, deploy. Then
delete `/var/lib/private/gatus` and `/srv/homelab/ts-gatus`, remove the
`gatus` node in the Tailscale admin console, and drop `gatus-env` +
the `GATUS_*` lines from `easy-afd-env` in sops.
