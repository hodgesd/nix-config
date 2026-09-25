# nixos-infra — architecture & disaster-recovery runbook

The `nixos-infra` VM (Proxmox guest on the HP mini PC; tailnet
`nixos-infra-1`, 100.98.163.36, LAN 192.168.1.216) is managed by this
repo: `hosts/nixos/nixos-infra/`. `/etc/nixos` on the VM is just a
pointer README — **this repo is authoritative**. Deploy from the Mac
with `just deploy` (see [Deploying](#deploying)).

> Migrated 2026-07-26 from the channel-based `hodgesd/homelab` repo
> (now archived). Pre-flake config preserved on the VM at
> `/etc/nixos.pre-flake.bak` until cleanup.

## Architecture

**Host services (NixOS modules in `hosts/nixos/nixos-infra/`):**

| Unit | Module | What | When |
|---|---|---|---|
| `easy-afd` | `easy-afd.nix` | Easy A/FD (gunicorn :8000, tailnet-only via firewall) | always |
| `nginx` | `proxy.nix` | TLS front for **https://afd.hdgs.me** (LE cert, DNS-01 via Cloudflare) | always |
| `easy-afd-refresh` | `easy-afd.nix` | Rebuilds NASR/OurAirports/openAIP data, restarts app, Gatus heartbeat | weekly (Mon ~00:45) |
| `homelab-backup` | `backup.nix` | Mirror /srv/homelab + secrets → NAS `backups` share | nightly 03:30 |
| `mnt-data.automount` | `storage.nix` | `//192.168.1.142/Data` at /mnt/data (MeTube downloads) | on access |
| `compose-homelab` | `homelab-stack.nix` | Deploys `stacks/homelab/docker-compose.yml` → `docker compose up -d` | on change |
| `acme-afd.hdgs.me` timers | `proxy.nix` | Cert renewal | automatic |
| `hermes-agent` | `hermes.nix` | NousResearch Hermes agent (Claude via Anthropic API): Telegram bot + host `hermes` CLI, container mode on the host docker daemon | always |
| `hermes-watchdog` | `hermes.nix` | Checks hermes unit + container, alerts via ntfy (`hermes-alerts` topic) | every 5 min |
| `gatus` | `gatus.nix` | Monitoring + status page (:8080, tailnet-only): pings mini + NAS, polls all nine compose apps + Easy A/FD, heartbeat for the weekly refresh; alerts via ntfy (`gatus` topic). HTTPS via the `ts-status` sidecar → **https://status.jaguar-duckbill.ts.net** | always |
| `hc-heartbeat` | `healthchecks.nix` | Checks in with healthchecks.io (off-site dead-man for this VM) | every 5 min |
| `hc-ntfy` | `healthchecks.nix` | Checks in with a second healthchecks.io check only while ntfy's `/v1/health` is healthy (alerts when the alerter is down) | every 5 min |
| `samsclub-popcorn` | `samsclub-popcorn.nix` | **Temporary, expires 2026-12-12.** Curls a Sam's Club product page, alerts via ntfy (`changes` topic) when delivery from the O'Fallon club comes back in stock; after expiry it only reminds you to remove it. Manual test: `samsclub-popcorn-check --test` | every 2 h, 06–22 |

Shared server baseline (tailscale from locked unstable, docker_29,
openssh with LAN key, firewall trusting only `tailscale0`, Cachix
substituter) lives in `hosts/common/nixos-common.nix`.

**Docker estate (`stacks/homelab/docker-compose.yml` — authoritative;
deployed to /srv/homelab on every switch):** each app pairs with a
`ts-<name>` Tailscale sidecar (hostname = tailnet name, HTTPS via
`TS_SERVE_CONFIG` proxying 443 → app port). Apps: actual-budget
(`budget`), ntfy, adguardhome (`adguard`),
homepage, librespeed, metube, changedetection (`changes`; plus a
ports-less `sockpuppetbrowser` Chrome container it talks to over the
compose network), stirling-pdf (`pdf`), drawio. All reachable at
`https://<name>.jaguar-duckbill.ts.net`. Images are pinned as
`repo:tag@sha256:…` — the digest decides what runs, the tag is there so
Renovate can read the version.

**Image updates (Renovate):** `renovate.json` at the repo root. Every
Monday Renovate opens ONE grouped PR ("homelab images") with all
minor/patch/digest bumps and their release notes; major versions only get
a PR after you tick them on the Dependency Dashboard issue. Merging does
not deploy anything. Weekly routine: read the PR → merge → `git pull` →
`just deploy-check` → `just deploy` → watch Gatus. Rollback: `git revert`
the merge, `just deploy`. Snapshot the VM first for a major bump of a
stateful service (actual, adguard, changedetection, ntfy). Disable: remove
`renovate.json` or uninstall the Renovate GitHub app.

**Monitoring (Gatus, on this host):** `gatus.nix` — native `services.gatus`,
monitors declared in Nix, SQLite history under `/var/lib/gatus`, dashboard
at **https://status.jaguar-duckbill.ts.net** through the `ts-status`
sidecar. Pings the mini and the NAS, polls all nine compose apps and Easy A/FD by their
tailnet/public names, and holds a 192 h heartbeat for the weekly Easy A/FD
refresh (the refresh script POSTs to it; URL + token in `easy-afd-env`).
Alerts go to ntfy topic `gatus` after 3 consecutive failures, resolved after
2 successes. Uptime Kuma (2026-08 → 2026-09-06, on the mini) was replaced
after a side-by-side trial; `docs/GATUS-EVAL.md` has the mapping and the
reasons.

Things Gatus here cannot do, handled separately:

- **See this VM die.** Gatus and ntfy both live on the VM. `healthchecks.nix`
  checks in with healthchecks.io every 5 min; if the check-ins stop (VM,
  power, or internet down), healthchecks.io alerts through its own channels.
  Period 5 min, grace 5 min → ~10 min to alert.
- **See ntfy die.** Gatus alerts *through* ntfy, so a dead ntfy is silent.
  `hc-ntfy` pings a second healthchecks.io check only while ntfy's
  `/v1/health` (via its tailnet name) says healthy. Period 5 min, grace
  10 min, so a deploy's container recreate doesn't page.
- **Route to the sidecar directly.** Gatus is native, so `ts-status` reaches
  it over the compose bridge, which the firewall does not trust; `gatus.nix`
  adds one iptables rule for TCP 8080 from Docker's range. The LAN stays
  blocked.

`hermes-watchdog` (in `hermes.nix`) checks the Hermes unit + container
every 5 min with an edge-triggered ntfy alert. It won't catch a Telegram
poller wedged inside a healthy container — that would need a heartbeat into
a Gatus external endpoint (future work).

**DNS:** `hdgs.me` on Cloudflare (moved from Hover 2026-07-25). `afd` A
→ 100.98.163.36 (DNS-only; public name, tailnet-only reachability).
Email = Fastmail (MX/SPF/DKIM/DMARC). API token (zone-scoped, DNS edit)
in the `cloudflare-acme-env` secret for ACME + automation.

## Deploying

From the Mac (repo on `main`):

```bash
just deploy-check   # dry-activate: show what would change
just deploy         # eval local → copy drvs → build on VM → activate
```

The recipe activates inside a transient systemd unit so a tailscaled
restart mid-switch can't kill the activation. Rollback:
`sudo nixos-rebuild switch --rollback` on the VM, or pick the previous
generation in the systemd-boot menu (Proxmox console).

DR fallback when the Mac is unavailable — on the VM:

```bash
git clone https://github.com/hodgesd/nix-config && cd nix-config
sudo nixos-rebuild switch --flake .#nixos-infra
```

## Secrets (sops-nix)

Encrypted in `secrets/nixos-infra.yaml` (safe to commit — ciphertext).
Recipients in `.sops.yaml`: the Mac editing key
(`~/.config/sops/age/keys.txt`, **backed up in Apple Passwords** as
"sops age key — nix-config") and the VM's SSH host key. At activation,
sops-nix decrypts into tmpfs at `/run/secrets/`; decryption failure
aborts activation *before* any service restarts.

| Secret | Consumers |
|---|---|
| `easy-afd-env` | easy-afd, refresh (OPENAIP_API_KEY, AUTOROUTER_*, FAA_NMS_*, GATUS_REFRESH_PUSH_URL/TOKEN) |
| `healthchecks-env` | hc-heartbeat (HC_PING_URL), hc-ntfy (HC_NTFY_PING_URL) — each healthchecks.io ping URL is a credential |
| `cloudflare-acme-env` | ACME (CLOUDFLARE_DNS_API_TOKEN + propagation tuning) |
| `nas-backup-credentials` | /mnt/data mount + backup script (SMB user `nixos-backup`) |
| `homelab-env` | compose interpolation (TS_AUTHKEY for sidecars) |
| `hermes-env` | hermes-agent (ANTHROPIC_API_KEY, TELEGRAM_BOT_TOKEN, Telegram user-ID allowlist — kept in ciphertext because the repo is public) |
| `unifi-hermes-key` | mcp-unifi (read-only UniFi API key) |
| `fastmail-hermes-ro-token` | mcp-fastmail (read-only JMAP token) |
| `gatus-env` | gatus (GATUS_NTFY_TOPIC, GATUS_REFRESH_TOKEN — the same token sits in `easy-afd-env` so the refresh can push its heartbeat) |
| `hodgesd-password` | `hashedPasswordFile` (seeds login on fresh installs) |

Edit: `sops secrets/nixos-infra.yaml` (opens your editor decrypted,
re-encrypts on save), then `just deploy`.

**Host-key rotation:** if the VM is reinstalled, its host key changes →
`ssh-keyscan -t ed25519 <vm> | ssh-to-age`, update `.sops.yaml`, run
`sops updatekeys secrets/nixos-infra.yaml`, deploy.

## Backups (3 layers)

1. **Nightly file mirror** (`homelab-backup`, 03:30): /srv/homelab
   (minus `metube/downloads` — lives on NAS directly), hermes state
   `/var/lib/hermes`, plus a break-glass plaintext copy of the sops
   secrets → `//192.168.1.142/backups/nixos-infra/`. Containers paused
   seconds for SQLite consistency. (`/etc/nixos` is no longer mirrored —
   config lives in this repo on GitHub.)
2. **NAS snapshots**: `backups` share daily 05:00, keep 64 (~2 months).
   Restore a file = browse the snapshot in UniFi Drive.
3. **Proxmox vzdump** (weekly, mode=snapshot → NAS): whole-VM archive.
   Guest agent enabled in NixOS (`services.qemuGuest.enable`); tick
   "QEMU Guest Agent" in VM Options. Restore = pick archive → Restore →
   boot.

**Deliberately NOT backed up:** `/var/lib/easy-afd` (refresh scripts
rebuild it; `alternates.pickle` is pandas-version-coupled — NEVER copy
between machines) and `/mnt/data/Videos/MeTube` (regenerable media).

## Restore drills

- **One file:** UniFi Drive → Backups share → snapshot browser.
- **Whole VM:** Proxmox → storage → Backups → newest archive → Restore
  (same or new VMID) → boot. Verify /healthz + docker ps. Note: a
  restored VM keeps its host key, so sops still decrypts.
- **From scratch (no vzdump):** install NixOS 26.05 (the flake's release;
  `system.stateVersion` stays "25.11" — never bump it) → clone this repo →
  **rotate the sops host key** (see above; needs the Mac age key, or
  restore secrets from the NAS `nixos-infra/secrets/` plaintext mirror)
  → copy `hardware-configuration.nix` from the new install into
  `hosts/nixos/nixos-infra/` if disk UUIDs changed →
  `sudo nixos-rebuild switch --flake .#nixos-infra` → restore
  /srv/homelab from NAS mirror (compose comes up via `compose-homelab`)
  → rsync app source from dev Mac (`deploy.sh` in the gvii_afd repo) →
  run refresh scripts. Tailscale: `tailscale up --ssh` and re-auth;
  sidecars re-auth via TS_AUTHKEY (mint a new one if expired, update the
  `homelab-env` secret).
- **changedetection.io:** `/srv/homelab/changedetection` (from the NAS
  mirror) is the whole state — watches, history, password, notification
  URLs. The sidecar identity is `/srv/homelab/ts-changes`. Notification
  priority is set per tag, not globally (since 2026-09-14): the `software`
  tag posts `ntfys://ntfy.jaguar-duckbill.ts.net/changes?priority=low`
  (silent on iPhone) and `price` posts `?priority=high`. The global URL
  (default priority) only applies to untagged watches.

## Gotchas (hard-won)

- **Nix `let`-block trap:** config attrs (e.g. `fileSystems.*`) pasted
  into the module's `let` section become unused local variables —
  silently, no error, identical rebuild closure. Config goes in the
  module body. Check the store path changed after rebuild.
- **Gatus is native, its sidecar is not.** A `ts-<name>` sidecar normally
  shares a network namespace with its app and proxies to 127.0.0.1. Gatus
  runs on the host, so `ts-status` proxies to `host.docker.internal` and
  the traffic arrives on the compose bridge, which the firewall does not
  trust — hence the iptables rule in `gatus.nix`. Also: `ntfy.priority`
  must be an integer (a string crashes Gatus at start, and `deploy-check`
  never runs the binary), and to fail an endpoint for an alert test use a
  closed port, not a 404 path — SPAs return 200 for anything.
- **UNAS SMB auth:** username is auto-generated (`nixos-backup`), and
  the password is set via "Reset Password" under File Services creds —
  not the account's display name/password. Auth failures = STATUS_LOGON_FAILURE.
- **Fresh Cloudflare zones can take ~30 min to publish new records**
  right after activation (ACME DNS-01 times out). Propagation timeout
  raised via `CLOUDFLARE_PROPAGATION_TIMEOUT` in the ACME env file.
- **tailscale serve vs nginx:** both want :443 on the tailnet IP —
  serve was disabled when nginx took over TLS for afd.hdgs.me.
- **MeTube:** downloads bind to /mnt/data (NAS); `STATE_DIR=/state`
  stays local — queue DB must not live on SMB. "Best" quality can yield
  AV1 (no hw decode before A17 Pro/M3); force H.264 via the UI Codec
  dropdown if older devices complain.

New since the flake migration (2026-07-26):

- **Flakes only see git-tracked files.** A brand-new file (e.g. a
  secrets yaml) is invisible to `nix eval`/`build` until `git add` —
  the error is a confusing "path does not exist".
- **Don't deploy with `nix run nixpkgs#nixos-rebuild`:** the registry
  `nixpkgs` is unpinned and drifted to `nixos-rebuild-ng`, whose macOS
  wrapper is broken. The `just deploy` recipe does the pipeline
  explicitly (eval → `nix copy --derivation` → remote realise →
  `switch-to-configuration` in a systemd-run unit).
- **Activation over tailscale SSH can die mid-switch** if the switch
  restarts tailscaled — always activate inside `systemd-run` (the deploy
  recipe does).
- **Changing a compose image string recreates the container** even when
  it resolves to the identical image (config-hash change). Bind mounts
  and sidecar state survive; expect a ~30 s blip.
- **Tailscale sidecar HTTPS needs both stanzas** in `serve.json`: the
  `Web` handler *and* `TCP: {"443": {"HTTPS": true}}`. Without the TCP
  section, 443 is refused (this is how adguard's HTTPS URL was silently
  broken pre-migration).
- **Two sidecars have nix-generated serve.json** (`ts-status` from
  `gatus.nix`, `ts-changes` from `changedetection.nix`), bind-mounted
  from `/etc`; the rest are hand-made under `/srv/homelab/ts-<name>/config`.
  After changing a generated one, `docker restart ts-<name>` — compose
  does not recreate a container for a bind mount's contents.
- **`mnt-data.automount` can't be "reloaded"** — switch-to-configuration
  exits 4 when it tries; `systemctl restart mnt-data.automount` is the
  fix and the mount itself is unaffected.
- **A release upgrade makes `just deploy` look like it failed, twice.**
  Seen on 25.11 → 26.05 (2026-09-15): the switch restarts sshd, so the ssh
  session dies mid-activation and the recipe prints "activation unit
  failed" — check `systemctl show -p Result nixos-deploy` (it was
  `success`) and `readlink /run/current-system` before believing it. And
  switch-to-configuration exits 4 on "Failed to reload dbus-broker.service"
  because 26.05 switches D-Bus implementations; the reboot the upgrade
  needs anyway clears it. `hc-ntfy` also fails once per deploy: ntfy is
  down while docker restarts. The next timer run recovers it.

## Related

- App repo: `github.com/hodgesd/gvii_afd-backup` (deploy via its
  `deploy.sh`; /healthz shows deployed SHA + data ages)
- Dashboards: homepage `https://homepage.jaguar-duckbill.ts.net`,
  Gatus `https://status.jaguar-duckbill.ts.net`
- Machine registry entry: `lib/machines.nix` (`nixos-infra`)
