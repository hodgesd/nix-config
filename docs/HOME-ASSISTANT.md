# Home Assistant Yellow

The house runs on a Home Assistant Yellow (Raspberry Pi CM4, eMMC boot, no
NVMe) at `192.168.1.73` on the LAN and `homeassistant` /
`100.100.120.31` on the tailnet. HA answers on `:8123`, plain HTTP, over
both — the tailnet is WireGuard-encrypted end to end, so there is no
TLS in front of it (see "Tailscale Serve" under Known issues).

**It is an appliance, not a NixOS host.** Home Assistant OS is an
immutable buildroot image whose Supervisor runs Core and the add-ons as
containers. Nothing about the box is expressible in this flake; the repo
owns exactly one thing for it — the `yellow` group in
`hosts/nixos/nixos-infra/gatus.nix`. Everything else below is manual,
through the HA UI or the `ha` CLI over SSH, and is written down here
because there is nowhere else declarative to put it.

Revived 2026-09-19 after 14 months unmaintained (Core 2025.7.3 → 2026.9.3,
HAOS 15.2 → 18.3, HACS 1.32.1 → 2.0.5). The upgrade went through two Core
hops with a verified off-box backup in front of each. Nothing broke.

## Access

| Path | How | Notes |
|---|---|---|
| Web UI | `http://homeassistant.jaguar-duckbill.ts.net:8123` (tailnet) or `http://homeassistant.local:8123` (LAN) | |
| SSH | `ssh root@homeassistant.jaguar-duckbill.ts.net` | Terminal & SSH add-on (`core_ssh`), key-only, `password` empty |
| `ha` CLI | in that shell | the only thing that drives OS/Core/add-on updates and backups |

The Tailscale add-on (`a0d7b954_tailscale`) is the remote path: *start on
boot* on, *watchdog* on, *autoupdate* off. Terminal & SSH is the same:
boot auto, autoupdate off. **Neither lifeline add-on auto-updates** — an
unattended update that breaks one removes the tool you would fix it with.

Port 22 is bound on the host, so SSH is reachable on the LAN too, not
only over the tailnet; that is the one deviation from the "tailnet
interface only" rule and is accepted because auth is key-only. To close
it: Terminal & SSH → Configuration → Network → clear the `22/tcp` host
port → restart (the web terminal through Ingress keeps working).

Two things the CLI cannot do, learned the hard way:

- **`ha addons options` does not exist** (CLI 4.x and 5.5 alike). Add-on options are
  set with the Supervisor API from inside the SSH shell, and the body
  must be the *full* options object — a partial one fails schema
  validation:
  ```
  TOK=$(cat /run/s6/container_environment/SUPERVISOR_TOKEN)
  curl -s -H "Authorization: Bearer $TOK" http://supervisor/addons/<slug>/info \
    | jq '{options: (.data.options | .<key> = <value>)}' \
    | curl -s -X POST -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' \
        http://supervisor/addons/<slug>/options --data-binary @-
  ```
- **The SSH add-on cannot update itself** (`403 App core_ssh can't update
  itself!`). Update it from the UI: Settings → Add-ons → Terminal & SSH →
  Update. SSH drops for ~30 s and comes back with the keys intact.

## Layers and update policy

| Layer | Now | Auto-update? | Policy |
|---|---|---|---|
| Supervisor | 2026.09.2 | mandatory | leave it |
| HAOS | 18.3 | no | manual; A/B slot (RAUC) falls back on a failed boot; **needs a reboot** — pick when the house goes quiet |
| Core | 2026.9.3 | no toggle exists | **manual, always.** Recorder DB schema migrations are one-way |
| Add-ons | ssh 9.18.0, tailscale 0.30.0 | per add-on | off for the two lifelines above; on for anything else |

Automate the *awareness* and the *backup*, never the Core update. The
14-month hole came from missing awareness, not missing automation — see
"Notifications".

### Monthly procedure (≈20 min when current)

1. Read the release's *backward-incompatible changes*
   (`https://www.home-assistant.io/blog/…/release-YYYYM/`); the
   changedetection watch on the release-notes category flags new posts.
2. `ha backups new --filename pre_core_<version>.tar`, then `scp` it to
   the Mac / UNAS and compare `sha256sum` — a backup on the Yellow does
   not survive the Yellow.
3. `ha os update` if offered → `ha host reboot` (the OS update only
   *stages*; `version_pending` clears after the reboot).
4. `ha core update --version <X> --backup`.
5. Verify: `ha core info` version; `ha core logs | grep -iE "Setup
   failed|Unable to set up"` empty; no new `ERROR` sources; ConBee still
   at `/dev/serial/by-id/usb-dresden_elektronik…`; Overview renders.
6. Add-ons last; the SSH one from the UI.

If more than ~3 releases behind, hop via the last release of each year.

## Backups

Three verified tars from the revival live on the Mac at
`~/Backups/homeassistant/` (`pre_upgrade_2026-09-19`, `pre_core_2025-12-05`,
`pre_core_2026-09-03`); copy them to the UNAS `backups` share. They are
**unencrypted** — no key needed to restore.

**Scheduled backups have never been configured** (`recurrence: never`).
To set up: Settings → System → Storage → *Add network storage* →
`//192.168.1.142/backups`, usage *Backup*, with its own NAS user scoped
to that share (not `nixos-backup`, which `backup.nix` uses — keep the
two independently revocable). Then Settings → System → Backups → *Set
up backups*: daily, retention ~7, that location. When encryption is
turned on, the key is shown **once** — put it in the password manager
before clicking anything else.

## Zigbee

Coordinator: a **ConBee II USB dongle** on `/dev/ttyACM0`
(`/dev/serial/by-id/usb-dresden_elektronik_ingenieurtechnik_GmbH_ConBee_II_DE2292798-if00`),
driven by ZHA with `radio_type: deconz`. Three end devices, all Third
Reality 3RSP02028BZ smart plugs (power-monitoring), plus the coordinator:
`Outlet_Kobalt` (Dining Room), `Mac Mini Outlet` (Office),
`Outlet_Dell_R720U` (Basement, on a Dell R720 server). All three are on
firmware `0x1001305c`; `0x10013065` is offered. HA calls deCONZ
"deprecated hardware with end-of-life firmware" and warns it degrades
past ~15–20 devices; at three it is fine.

The Yellow's **onboard Silicon Labs radio (`/dev/ttyAMA1`) is unused.**
Migrating ZHA onto it (Settings → ZHA → *Migrate radio*, or backup/restore
of the coordinator) is a worthwhile, modest follow-up — with four devices
even a full re-pair of three plugs is a short job. Never run the multiprotocol
(Zigbee+Thread) firmware on it; that path is unstable and unsupported.

Device firmware updates are OTAs to end devices — slow and
mesh-dependent, one at a time, nothing else in flight. The three plugs
are the same model, so the same OTA will come up for each: do `Mac Mini
Outlet` first (it powers a retired machine), and `Outlet_Dell_R720U` last,
when the server can tolerate a relay glitch. A *coordinator* firmware update is a different animal: its own
day, its own backup.

## Monitoring

`gatus.nix` group `yellow`: ICMP to `100.100.120.31` and HTTP to
`http://homeassistant.jaguar-duckbill.ts.net:8123/manifest.json` (200
without auth — no HA token in sops for this). Both go over the tailnet
on purpose, so the Tailscale add-on is exercised by every poll. Alerts go
to the shared ntfy channel like everything else. The Yellow is a separate
box, so Gatus can genuinely observe it dying; no dead-man needed.

**Disable:** delete the two `yellow` lines from `gatus.nix`,
`just deploy`.

## Notifications (to do)

- **New release available:** native `ntfy` integration (Settings →
  Integrations → Add → *ntfy*, URL `https://ntfy.jaguar-duckbill.ts.net`,
  a low-priority topic) plus an automation on `update.home_assistant_core_update`
  → `on` calling `notify.send_message`. Low priority: on the iPhone,
  ntfy 1–2 is silent and 3–5 all look the same.
- **What is in a release:** changedetection watch on
  `https://www.home-assistant.io/blog/categories/release-notes/`, tag
  `software` — **to do**: add it in the changedetection UI (API key is not wired into /run/secrets).

## Configuration

`/config/configuration.yaml` is 11 lines of includes plus an `http:` block
(`use_x_forwarded_for` + `trusted_proxies: [127.0.0.1, ::1]`) that is
harmless today and required the moment Tailscale Serve works. Everything
else — devices, entities, dashboards, most automations — is UI-managed
JSON in `/config/.storage/`, which is **never hand-edited**.

`/config` is a git repo on the box (first commit "as found after
upgrade"; `.gitignore` drops `.storage/`, `secrets.yaml`, `*.db*`, logs,
`backups/`, `deps/`, `tts/`, `www/community/`). It tracks YAML plus
`custom_components/` — which pins the exact HACS version. No remote yet;
add one if you want it off-box (the backups already cover it).

Only custom component: **HACS 2.0.5**, with nothing installed through it.
Its 1.32.1 predecessor is parked at `/config/hacs.bak-1.32.1` for
rollback and inflates every backup by ~20 MB — `rm -rf` it once 2.0.5 has
been fine for a while.

## Known issues and follow-ups

- **Tailscale Serve** (`share_homeassistant: serve`, HTTPS on 443 inside
  the tailnet) **put add-on 0.30.0 into `state: error`** and dropped the
  tailnet path; reverted to `disabled`. The startup log was lost to the
  restart. To diagnose: over the LAN path, set `serve` with the API
  snippet above, `ha addons start a0d7b954_tailscale`, and *immediately*
  `ha addons logs a0d7b954_tailscale` to catch the failing step; revert
  is ~10 s. Not urgent — it buys a lock icon and parity with the `ts-*`
  sidecars, not security.
- **Reolink:** "Back Left" (`192.168.1.41`) is offline outright (bootstrap
  waited 21 min on it); all three cameras (`.41`, `.87`, `.19`) also drop
  weekly around **01:59–02:00 on Sundays** — some scheduled network
  event, not HA.
- **iCloud** integration password expired (pre-existing): Settings →
  Integrations → iCloud → *Configure*.
- **Tailscale key expiry** for the `homeassistant` node should be
  disabled in the admin console, or it silently leaves the tailnet in
  ~180 days.
- `external_url` is unset: Settings → System → Network →
  `http://homeassistant.jaguar-duckbill.ts.net:8123`.
- Homepage tile: the gethomepage `homeassistant` widget needs a
  long-lived token (Profile → Security), the one token this box hands
  out. Homepage config is runtime state on the VM, not the repo.

## Credential inventory (names and scopes only)

| Credential | Where | Scope |
|---|---|---|
| SSH key `hodgesd@mbp` | Terminal & SSH add-on `authorized_keys` | root shell on the Yellow |
| Tailscale node key `homeassistant` | tailnet | tailnet membership; disable expiry |
| *(pending)* NAS user for backups | UNAS | `backups` share only |
| *(pending)* HA long-lived token `homepage` | Homepage config on the VM | HA REST/WebSocket as the creating user |

No HA credential lives in this repo or in sops.
