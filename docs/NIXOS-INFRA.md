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
| `easy-afd-refresh` | `easy-afd.nix` | Rebuilds NASR/OurAirports/openAIP data, restarts app, Kuma heartbeat | weekly (Mon ~00:45) |
| `easy-afd-healthcheck` | `easy-afd.nix` | Curls own /healthz via public name → Kuma heartbeat | every 60 s |
| `homelab-backup` | `backup.nix` | Mirror /srv/homelab + secrets → NAS `backups` share | nightly 03:30 |
| `mnt-data.automount` | `storage.nix` | `//192.168.1.142/Data` at /mnt/data (MeTube downloads) | on access |
| `compose-homelab` | `homelab-stack.nix` | Deploys `stacks/homelab/docker-compose.yml` → `docker compose up -d` | on change |
| `acme-afd.hdgs.me` timers | `proxy.nix` | Cert renewal | automatic |

Shared server baseline (tailscale from locked unstable, docker_29,
openssh with LAN key, firewall trusting only `tailscale0`, Cachix
substituter) lives in `hosts/common/nixos-common.nix`.

**Docker estate (`stacks/homelab/docker-compose.yml` — authoritative;
deployed to /srv/homelab on every switch):** each app pairs with a
`ts-<name>` Tailscale sidecar (hostname = tailnet name, HTTPS via
`TS_SERVE_CONFIG` proxying 443 → app port). Apps: uptime-kuma
(`uptime`), actual-budget (`budget`), ntfy, adguardhome (`adguard`),
homepage, librespeed, metube. All reachable at
`https://<name>.jaguar-duckbill.ts.net`. Images are **pinned by digest**
(human version in a trailing comment). To upgrade one: set its image to
a tag, `just deploy`, then re-pin to the new digest
(`docker image inspect --format '{{index .RepoDigests 0}}' <image>`).

**Monitoring (Uptime Kuma at http://uptime:3001):** the Kuma container
cannot reach tailnet IPs (firewall trusts only tailscale0), so Easy A/FD
monitors are **push-based dead-man switches**: `afd-healthz` (3-min
window) and `easy-afd-refresh` (8-day window). Push URLs live in the
`easy-afd-env` secret.

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
| `easy-afd-env` | easy-afd, refresh, healthcheck (OPENAIP_API_KEY, AUTOROUTER_*, KUMA_*_PUSH_URL) |
| `cloudflare-acme-env` | ACME (CLOUDFLARE_DNS_API_TOKEN + propagation tuning) |
| `nas-backup-credentials` | /mnt/data mount + backup script (SMB user `nixos-backup`) |
| `homelab-env` | compose interpolation (TS_AUTHKEY for sidecars) |
| `hodgesd-password` | `hashedPasswordFile` (seeds login on fresh installs) |

Edit: `sops secrets/nixos-infra.yaml` (opens your editor decrypted,
re-encrypts on save), then `just deploy`.

**Host-key rotation:** if the VM is reinstalled, its host key changes →
`ssh-keyscan -t ed25519 <vm> | ssh-to-age`, update `.sops.yaml`, run
`sops updatekeys secrets/nixos-infra.yaml`, deploy.

## Backups (3 layers)

1. **Nightly file mirror** (`homelab-backup`, 03:30): /srv/homelab
   (minus `metube/downloads` — lives on NAS directly) plus a break-glass
   plaintext copy of `/run/secrets/*` →
   `//192.168.1.142/backups/nixos-infra/`. Containers paused seconds for
   SQLite consistency. (`/etc/nixos` is no longer mirrored — config
   lives in this repo on GitHub.)
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
- **From scratch (no vzdump):** install NixOS 25.11 → clone this repo →
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

## Gotchas (hard-won)

- **Nix `let`-block trap:** config attrs (e.g. `fileSystems.*`) pasted
  into the module's `let` section become unused local variables —
  silently, no error, identical rebuild closure. Config goes in the
  module body. Check the store path changed after rebuild.
- **Kuma can't poll tailnet/host services** (docker bridge ≠ trusted
  interface) → use push monitors, not HTTP monitors, for things here.
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
- **`mnt-data.automount` can't be "reloaded"** — switch-to-configuration
  exits 4 when it tries; `systemctl restart mnt-data.automount` is the
  fix and the mount itself is unaffected.

## Related

- App repo: `github.com/hodgesd/gvii_afd-backup` (deploy via its
  `deploy.sh`; /healthz shows deployed SHA + data ages)
- Dashboards: homepage `https://homepage.jaguar-duckbill.ts.net`,
  Kuma `http://uptime:3001`
- Machine registry entry: `lib/machines.nix` (`nixos-infra`)
