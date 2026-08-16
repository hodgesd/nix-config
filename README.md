# 🛠️ My Nix Config

A modular Nix flake managing **all my machines**: three Macs via nix-darwin and the
NixOS homelab VM via the same repo — one lockfile, shared modules, machine metadata
for conditional config.

## ✨ Features

- 🔧 Modular configuration structure
- 🤖 Machine metadata system for conditional configs (`lib/machines.nix`)
- 📦 Declarative package management (Nix + Homebrew on macOS)
- 🏠 Home Manager integration (macOS; opt-in per NixOS host)
- 🐧 NixOS homelab host deployed from the Mac over Tailscale
- 🔄 Easy rollbacks and reproducibility (generations on every machine)
- ✅ CI: every host is evaluated and built on each PR, pushed to Cachix

## 📖 Documentation

- **[STRUCTURE.md](docs/STRUCTURE.md)** - Configuration layout and organization
- **[ADDING_MACHINE.md](docs/ADDING_MACHINE.md)** - Step-by-step guide to add new machines
- **[HOMEBREW.md](docs/HOMEBREW.md)** - Managing Homebrew packages and Mac App Store apps
- **[CUSTOMIZATION.md](docs/CUSTOMIZATION.md)** - Common customization tasks

## 💻 Machines

| Hostname      | OS | Model                    | User            | Storage (Ram/HD) | Cores (CPU/GPU) |
|---------------|----|--------------------------|-----------------|------------------|-----------------|
| `mbp`         | 🍏 | MacBook Pro M3 Pro 14"   | `hodgesd`       | 18GB / 1TB       | 12 / 18         |
| `mini`        | 🍏 | Mac Mini M2 Pro          | `derrickhodges` | —                |                 |
| `air`         | 🍏 | MacBook Air M1 13"       | `hodgesd`       | 16GB / 500GB     | 8 / 7           |
| `nixos-infra` | 🐧 | Proxmox VM (HP mini PC)  | `hodgesd`       | 39GB disk        |                 |

## 🍎 Mac Installation

### Fresh Install (recommended path)

On a brand-new Mac, `scripts/bootstrap.sh` does everything: Xcode CLT, Nix
(Determinate Systems installer), host validation, build, and activation.
Idempotent — safe to re-run.

```bash
git clone https://github.com/hodgesd/nix-config.git ~/nix-config
cd ~/nix-config && ./scripts/bootstrap.sh <hostname>
```

`<hostname>` must be one of the darwin machines above. Set the Mac's name first
(or let the script infer it from `hostname -s`):

```bash
./scripts/set_mac_name.sh
```

⏱️ **Expected time:** 15–30 minutes. Then restart your shell: `exec zsh`.

### Existing System (Mac with apps/data to preserve)

Same as above, but **before** running bootstrap:

1. Time Machine backup recommended.
2. Run the audit to identify apps at risk:
   ```bash
   ./scripts/pre_install_audit.sh
   ```
3. Add apps you want kept to `hosts/common/darwin/homebrew.nix` (`casks = [...]`)
   and make sure `onActivation.cleanup = "none"` while migrating.

After verifying everything works, find stragglers with
`./scripts/find_unmanaged_apps.sh` and optionally re-enable cleanup.

### Post-Install Configuration

**Wallpaper Rotation (mini)** — manual via System Settings:

1. Ensure folder exists (iCloud synced): `mkdir -p ~/Documents/Wallpapers`
2. **System Settings** → **Wallpaper** → add folder `~/Documents/Wallpapers/`,
   enable **"Change picture"** with desired interval.

**Hotkeys (skhd + Karabiner Elements)**

1. Launch Karabiner Elements: `open -a Karabiner-Elements`
2. Grant Accessibility permissions: **System Settings** → **Privacy & Security** →
   **Accessibility** → Enable `skhd` and `Karabiner-Elements`
3. skhd starts automatically at activation (`skhd --start-service` under the hood);
   if it didn't, run `/opt/homebrew/bin/skhd --start-service` manually.
4. Test: Press `shift + ctrl + alt + y` (creates `~/skhd-test.log`)

**Note:** Enable "Launch at login" in Karabiner Elements preferences.

**Manual App Setup**
- Reminders Menubar: enable "Launch at login"; bind `meh-r`.
- iStat Menus: add registration key.
- Launch at login: Raycast, Rectangle, SwiftBar, Ice.

**Manually Installed Apps**

- [llm](https://llm.datasette.io/en/stable/) - CLI for LLMs with MLX support
  ```bash
  uv tool install llm --with sentencepiece
  llm install llm-mlx llm-hacker-news
  llm mlx download-model mlx-community/Mistral-7B-Instruct-v0.3-4bit
  llm aliases set m7b mlx-community/Mistral-7B-Instruct-v0.3-4bit
  llm models default m7b
  ```

## 🐧 NixOS Homelab (`nixos-infra`)

A Proxmox guest VM on the HP mini PC, fully managed by this flake
(`hosts/nixos/nixos-infra/`). It runs:

- **easy-afd** — Flask/gunicorn app behind nginx with a Let's Encrypt DNS-01 cert
  (`afd.hdgs.me`, tailnet-only reachability)
- **Docker compose estate** (`/srv/homelab`) — 6 apps, each with a Tailscale
  sidecar: Actual Budget, Homepage, ntfy, AdGuard Home, LibreSpeed, MeTube
  (compose snapshot: `stacks/homelab/docker-compose.yml`). Uptime Kuma moved
  to the mini so the monitor outlives the host it watches
  (`stacks/uptime/docker-compose.yml`)
- **Hermes agent** (NousResearch) — Claude-backed agent in a container on the
  host docker daemon; Telegram bot front end + `hermes` CLI on the VM
- **Nightly NAS backups** (03:30 → UNAS Pro 8) and weekly aeronautical-data refresh

### Deploying (from the Mac)

The Mac evaluates the flake; the VM builds and activates (the Mac can't build
x86_64-linux). Runs as root over Tailscale SSH — no password prompts:

```bash
just deploy-check   # dry-activate: show what would change
just deploy         # build + switch
```

Rollback on the VM: `sudo nixos-rebuild switch --rollback`, or pick the previous
generation in the systemd-boot menu from the Proxmox console.

### DR fallback (Mac unavailable)

On the VM itself:

```bash
git clone https://github.com/hodgesd/nix-config && cd nix-config
sudo nixos-rebuild switch --flake .#nixos-infra
```

### Notes

- `/etc/nixos` on the VM is just a pointer README — this repo is authoritative.
  (Pre-flake config preserved at `/etc/nixos.pre-flake.bak` for now.)
- LAN SSH (`hodgesd@192.168.1.216`) is key-only and independent of Tailscale —
  the break-glass path if the tailnet is down. Proxmox console is the last resort.
- Secrets are root-only files on the VM (`/etc/easy-afd.env`,
  `/etc/cloudflare-acme.env`, `/etc/nas-backup.credentials`, `/srv/homelab/.env`),
  mirrored nightly to the NAS. Migration to sops-nix is in progress.
- The easy-afd **app source** (`/srv/easy-afd`) is rsynced from the dev Mac and is
  *not* managed by Nix — a from-scratch rebuild needs that rsync before the
  service starts.

## 🚀 Quick Commands

```bash
# Macs: build and switch current host (uses justfile)
just

# Macs: build only (no activation)
just build

# Homelab: dry-run / deploy from the Mac
just deploy-check
just deploy

# Update flake inputs (get latest packages)
just update

# Garbage collect generations older than 14 days
just gc

# Format nix files
nix fmt

# Rollback (macOS / NixOS)
darwin-rebuild switch --rollback
sudo nixos-rebuild switch --rollback
```

## 📁 Configuration Structure

```
nix-config/
├── flake.nix              # Inputs + darwin/nixos configurations + formatter
├── lib/
│   ├── machines.nix       # Machine metadata registry (all machines)
│   ├── helpers.nix        # mkDarwin + mkNixos builders
│   └── options.nix        # majordouble.* option schema
├── hosts/
│   ├── common/
│   │   ├── common-packages.nix   # Cross-platform CLI set (+ darwin-only extras)
│   │   ├── darwin-common.nix     # macOS entry point
│   │   ├── nixos-common.nix      # NixOS server baseline
│   │   └── darwin/               # macOS modules (homebrew, defaults, desktop…)
│   ├── darwin/<host>/     # Per-Mac overrides
│   └── nixos/<host>/      # Per-NixOS-host config (hardware, services…)
├── home/                  # Home Manager configurations (portable)
├── modules/               # Custom modules (swiftbar, wallpaper…)
├── stacks/                # Docker compose stacks (homelab, arr-stack)
├── scripts/               # bootstrap + audit helper scripts
└── docs/                  # Documentation
```

See [STRUCTURE.md](docs/STRUCTURE.md) for detailed information.

## 🔧 Common Tasks

- **Add a package (all machines)**: Edit `hosts/common/common-packages.nix`
- **Add Homebrew app**: Edit `hosts/common/darwin/homebrew.nix`
- **Change dock**: Edit `hosts/common/darwin/defaults/dock.nix` or host config
- **Modify macOS settings**: Edit files in `hosts/common/darwin/defaults/`
- **Add keyboard shortcut**: Edit `hosts/common/darwin/desktop/skhd.nix`
- **Change a homelab service**: Edit `hosts/nixos/nixos-infra/*.nix`, then `just deploy-check`
- **Add a new machine**: See [ADDING_MACHINE.md](docs/ADDING_MACHINE.md)
- **Audit installed apps**: Run `./scripts/find_unmanaged_apps.sh` (after nix-darwin installed)
- **Pre-install audit**: Run `./scripts/pre_install_audit.sh` (before nix-darwin installed)

For more, see [CUSTOMIZATION.md](docs/CUSTOMIZATION.md).

## 🛡️ Safety Features

- **Rollback capability**: Every change creates a new generation you can roll back to
- **Declarative**: Configuration is version-controlled and reproducible
- **CI before switch**: every host evaluates + builds on each PR (Cachix-cached)
- **App protection**: Set `cleanup = "none"` in homebrew.nix to prevent app removal

## 📝 Helper Scripts

- **`scripts/bootstrap.sh`** - Fresh Mac → fully-activated nix-darwin, idempotent
- **`scripts/pre_install_audit.sh`** - Audit system BEFORE installing nix-darwin
- **`scripts/find_unmanaged_apps.sh`** - Find apps not managed by nix AFTER installation
- **`scripts/set_mac_name.sh`** - Set hostname to match configuration
