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
| Supervisor | 2026.09.3 | mandatory | leave it |
| HAOS | 18.3 | no | manual; A/B slot (RAUC) falls back on a failed boot; **needs a reboot** — pick when the house goes quiet |
| Core | 2026.9.4 (2026-10-03) | no toggle exists | **manual, always.** Recorder DB schema migrations are one-way |
| Add-ons | ssh 10.5.0, tailscale 0.30.1 | per add-on | off for the two lifelines above; on for anything else |

Automate the *awareness* and the *backup*, never the Core update. The
14-month hole came from missing awareness, not missing automation — see
"Notifications".

### Monthly procedure (≈20 min when current)

1. Read the release's *backward-incompatible changes*
   (`https://www.home-assistant.io/blog/…/release-YYYYM/`); the
   changedetection watch on the release-notes category flags new posts.
2. Make sure a fresh backup exists **off the box** — a backup on the
   Yellow does not survive the Yellow. Since 2026-10-03 the nightly
   automatic backup lands on the UNAS (see Backups); check last night's is
   there, or trigger one now (Settings → System → Backups → *Backup now* →
   automatic settings). The older manual route still works: `ha backups
   new --filename pre_core_<version>.tar`, `scp`, compare `sha256sum`.
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
**unencrypted** — no key needed to restore. The same three are the only
ones left in `/backup` on the box: on 2026-09-20 the ten others (2022–2025
partials from Core versions that can no longer be restored, two 20 KB
add-on stubs, and the two automatic pre-update backups `--backup` made
during the hops) were removed with `ha backups remove <slug>` after the
keepers' `sha256sum` matched the Mac copies. `ha backups reload` afterwards
makes the Supervisor re-scan the directory.

**Scheduled backups run nightly since 2026-10-03.** Network storage
`unas_backups` (Settings → System → Storage) mounts
`//192.168.1.142/backups/homeassistant` — a peer of `nixos-infra/` on the
same share, so the share's 05:00 snapshots (keep 64) cover it too. The
*Remote share* field takes the subfolder (`backups/homeassistant`); the
folder must exist first. It signs in as its own NAS user `ha-backup`
(Editor on `Backups` only), not `nixos-backup`, which `backup.nix` uses
— the two stay independently revocable.

Automatic backups: daily at **02:30** (clear of the VM's 03:30 mirror and
the 05:00 snapshot), keep 7, written to both the UNAS and the Yellow,
with database, add-ons and the share/ssl/media folders. The first one
(`Automatic backup 2026.9.3`, ~59 MB) was verified on both locations.
They are **unencrypted**, like the revival tars. To encrypt: Settings →
System → Backups → backup settings; the key is shown **once** — put it
in the password manager before clicking anything else.

Nothing watches this job yet. `sensor.backup_last_successful_automatic_backup`
is the thing to alert on (see "Notifications").

A `STATUS_LOGON_FAILURE` in `ha host logs` when adding the storage is the
same UNAS quirk as in NIXOS-INFRA.md: set the password with *Reset
Password* under the person's File Services credentials.

## Zigbee

Coordinator: a **ConBee II USB dongle** on `/dev/ttyACM0`
(`/dev/serial/by-id/usb-dresden_elektronik_ingenieurtechnik_GmbH_ConBee_II_DE2292798-if00`),
driven by ZHA with `radio_type: deconz`, channel 15. Two end devices, both
Third Reality 3RSP02028BZ smart plugs (power-monitoring), plus the
coordinator: `Outlet_Kobalt` (Dining Room) and `Mac Mini Outlet` (Office).
A third, `Outlet_Dell_R720U` (Basement, on a decommissioned Dell R720),
had been off the mesh since 2026-02-21 and was removed from ZHA on
2026-10-03. Both are on firmware `0x1001305c`; `0x10013065` is offered.
HA calls deCONZ "deprecated hardware with end-of-life firmware" and warns
it degrades past ~15–20 devices; at two it is fine.

**`Outlet_Kobalt` has been off the mesh since 2025-12-01** (ZHA
`last_seen`). It is still wanted: check it has power; if it does not
rejoin, hold its button ~10 s and Settings → Devices & services → Zigbee →
*Add device* (same IEEE, so it keeps its name and entities).

The Yellow's **onboard Silicon Labs radio (`/dev/ttyAMA1`) is unused.**
Migrating ZHA onto it (Settings → ZHA → *Migrate radio*, or backup/restore
of the coordinator) is a worthwhile, modest follow-up — with three devices
even a full re-pair of two plugs is a short job. Never run the multiprotocol
(Zigbee+Thread) firmware on it; that path is unstable and unsupported.

Device firmware updates are OTAs to end devices — slow and
mesh-dependent, one at a time, nothing else in flight. The two plugs
are the same model, so the same OTA will come up for each. `Mac Mini
Outlet` powers a decommissioned machine, so its OTA is consequence-free;
`Outlet_Kobalt` is the only plug with something live behind it — do that
one last, once it is back on the mesh. A *coordinator* firmware update is
a different animal: its own day, its own backup.

## Integrations and automations (as of 2026-10-03)

Reviewed end to end on 2026-10-03 through the REST and WebSocket APIs;
the box was otherwise healthy (`supported`, `healthy`, 5.1 of 13.6 GB
used).

- **Cameras:** four Reolink entries (see Known issues for Front Right).
- **HomeKit:** `HASS Bridge:21064` is the one real bridge — include mode,
  exposing `climate.daikinap69200`; paired with Apple Home 2026-10-03.
  Each camera stream is its own accessory-mode entry (`Front sub`,
  `Back Left sub`, `Rear Right sub`, `Front Right sub`, `Front main`),
  paired separately. **Never delete or re-pair those.**
- **Garage mini-split:** Daikin FTXV18AVJU9 through the HACS custom repo
  `frogfrogfrogfrogfrogfrog/daikinskyport-deneb` (commit `e979ed9`), entity
  `climate.daikinap69200` ("Garage Mini Split").
- **Others:** ZHA, Wemo (`switch.grandfather`, unreachable — still wanted,
  needs power/Wi-Fi checked), Met.no, Electricity Maps, the phone app
  (`Gemini Mobile`, the only tracker behind `person.derrick`; the iPad
  re-registered itself as `Omilu iPad Pro New` after its old registration
  was removed).
- **One automation:** "Control Smart Plug with Solar Conditions" (id
  `1750757838877`) — `switch.outlet_kobalt_switch` on from 09:00 to 18:00
  while `weather.forecast_home` is `sunny` or `partlycloudy`, off
  otherwise; it skips while the plug is unavailable and re-evaluates when
  the plug returns. Rewritten 2026-10-03: the old version only accepted
  `sunny`, switched off at 19:00, fired on every forecast attribute
  change, and had been talking to an offline plug for ten months.
- **Removed 2026-10-03:** the iCloud integration (logged out since
  2024-12), the eero UPnP entry (never connected; eero keeps UPnP off),
  two stale phone-app registrations, the disabled "Kobolt on Solar"
  automation (its trigger could never match), and nine login sessions
  last used in 2022–2024. A backup named `Before cleanup 2026-10-03` on
  the Yellow precedes all of it.
- **Not connected yet:** the Tesla Powerwall and solar, the SPAN panel and
  the car — so the Energy dashboard is empty. Also discovered on the LAN
  and unused: two Hue bridges, Lutron Caseta (`192.168.1.100`), ecobee,
  the Apple TVs and HomePods, a Samsung TV, Litter-Robot, a Canon printer.

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

`/config/configuration.yaml` is 11 lines: `default_config`, the
`google_translate` TTS platform, and the three `!include`s. Everything
else — devices, entities, dashboards, most automations — is UI-managed
JSON in `/config/.storage/`, which is **never hand-edited**.

**There is no `http:` block, and adding one does nothing.** Since 2026.9
the `http` integration is configured from the UI (Settings → System →
Network) and stored in `/config/.storage/http`. On the first 2026.9.3
boot Core migrated whatever YAML existed (nothing) into that store and set
`yaml_migration_done`; from then on any `http:` YAML is **ignored
entirely** and only raises the repair "HTTP YAML configuration is ignored
after migration". A block with `use_x_forwarded_for` + `trusted_proxies`
was added during the revival, six minutes *after* that migration, so it
never took effect; it was removed on 2026-09-20 (`/config` commit
`60e89a5`) and Core restarted to clear the repair. Reverse-proxy trust
for the Tailscale add-on's loopback proxy (`127.0.0.1`, `::1`) has to be
set in that UI page, not in YAML.

`/config` is a git repo on the box (first commit "as found after
upgrade"; `.gitignore` drops `.storage/`, `secrets.yaml`, `*.db*`, logs,
`backups/`, `deps/`, `tts/`, `www/community/`). It tracks YAML plus
`custom_components/` — which pins the exact HACS version. No remote yet;
add one if you want it off-box (the backups already cover it).

Custom components: **HACS 2.0.5** and, installed through it on
2026-10-03, the Daikin `daikinskyport-deneb` integration (see above).
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
  sidecars, not security. **Before retrying**, set reverse-proxy trust
  under Settings → System → Network (see Configuration): during the
  trial HA had no trusted proxies at all — the YAML block meant to
  provide them was being ignored — and its log filled with "A request
  from a reverse proxy was received from 127.0.0.1, but your HTTP
  integration is not set-up for reverse proxies". Whether that alone is
  what made the add-on exit is unknown; it is the first thing to rule out.
- **Reolink:** four RLC-822A cameras — Front `192.168.1.87`, Back Left
  `.41`, Front Right `.38`, Back Right `.19`, all on firmware
  `v3.1.0.1643_2402219215` (2024-02). **"Front Right" (`.38`) is offline
  outright** — no HTTP, no RTSP — and Core's bootstrap waits up to ~27 min
  on it at every start (an earlier draft of this doc blamed Back Left;
  `.41` answers fine). Either bring the camera back or disable its
  config entry so restarts are quick. (The 2026.9.4 update on 2026-10-03
  reached `RUNNING` about two minutes after the new Core came up, with the
  entry still retrying.) All cameras also drop weekly around
  **01:59–02:00 on Sundays** — some scheduled network event, not HA.
- **`rpi_firmware_update_blocked`** (Settings → System → Repairs) is
  **permanent by design — ignore it.** The Supervisor sees a newer CM4
  bootloader EEPROM (`1767975133`, 2026-01, vs the installed `1638442201`,
  2021-12) but the OS agent reports `blocked_reason:
  eeprom_update_unavailable`: a CM4's EEPROM can only be flashed with
  `rpiboot` over USB (jumper set, module in USB-boot mode), never in
  place. There is no in-UI fix and never will be. State is at
  `GET http://supervisor/os/boards/raspberrypi/firmware` with the token
  from the SSH snippet above.
- **Phone app silent since 2026-01-11:** the iPhone's Home Assistant app
  last used its token that day, so `person.derrick` sits at `not_home`.
  The LAN moved from `192.168.7.x` to `192.168.1.x` since; check the
  app's server address (`http://homeassistant.local:8123`).
- **Tailscale key expiry** for the `homeassistant` node should be
  disabled in the admin console, or it silently leaves the tailnet in
  ~180 days.
- `external_url` is unset: Settings → System → Network →
  `http://homeassistant.jaguar-duckbill.ts.net:8123`.
- Homepage tile: the gethomepage `homeassistant` widget needs a
  long-lived token (Profile → Security), separate from the `Claude` one
  in the credential inventory. Homepage config is runtime state on the VM, not the repo.

## Credential inventory (names and scopes only)

| Credential | Where | Scope |
|---|---|---|
| SSH key `hodgesd@mbp` | Terminal & SSH add-on `authorized_keys` | root shell on the Yellow |
| Tailscale node key `homeassistant` | tailnet | tailnet membership; disable expiry |
| NAS user `ha-backup` | Home Assistant network storage `unas_backups` | Editor on the UNAS `Backups` share only |
| HA long-lived token `Claude` | `~/.config/home-assistant/token` on the MBP (mode 600) | HA REST/WebSocket as the owner account (admin) |
| *(pending)* HA long-lived token `homepage` | Homepage config on the VM | HA REST/WebSocket as the creating user |

No HA credential lives in this repo or in sops.
