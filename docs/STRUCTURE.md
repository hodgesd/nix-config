# Configuration Structure

This document explains the organization of this Nix configuration.

## Directory Layout

```
nix-config/
├── flake.nix              # Main flake file - darwin + nixos systems, formatter
├── .sops.yaml             # sops recipient policy (who can decrypt secrets)
├── secrets/               # sops-encrypted secrets (ciphertext, safe in git)
│   └── nixos-infra.yaml
├── lib/                   # Library functions and machine metadata
│   ├── default.nix        # Exports helper functions
│   ├── helpers.nix        # mkDarwin + mkNixos functions
│   ├── options.nix        # majordouble.* option schema
│   └── machines.nix       # Machine metadata registry (all machines)
├── hosts/                 # Host-specific configurations
│   ├── common/            # Shared configurations
│   │   ├── common-packages.nix      # Shared package set (+ darwin-only extras)
│   │   ├── darwin-common.nix        # Darwin entry point
│   │   ├── nixos-common.nix         # NixOS server baseline
│   │   └── darwin/                  # Darwin-specific modules
│   │       ├── base.nix             # Core Nix settings
│   │       ├── homebrew.nix         # Homebrew packages
│   │       ├── fonts.nix            # Font packages
│   │       ├── packages.nix         # Darwin packages
│   │       ├── system-defaults.nix  # System preferences
│   │       ├── desktop/             # skhd, karabiner, jankyborders, swiftbar
│   │       └── defaults/            # System defaults by category
│   │           ├── general.nix      # NSGlobalDomain settings
│   │           ├── keyboard.nix     # Keyboard/input settings
│   │           ├── finder.nix       # Finder preferences
│   │           ├── dock.nix         # Dock settings
│   │           └── security.nix     # Security/privacy settings
│   ├── darwin/            # Per-Mac overrides (optional; only mbp/ exists today)
│   │   └── mbp/default.nix
│   └── nixos/             # Per-NixOS-host config (REQUIRED per host)
│       └── nixos-infra/   # hardware-config, easy-afd, proxy, backup,
│                          # storage, homelab-stack
├── home/                  # Home Manager configurations (portable)
│   ├── default.nix        # User configuration entry point
│   └── modules/           # Tool configs (core, cli, services)
├── modules/               # Custom modules
│   ├── swiftbar.nix       # HM module (macOS)
│   ├── wallpaper.nix      # HM module (macOS)
│   ├── nixos/compose-stack.nix   # nix-owned docker compose stacks (systemd)
│   └── darwin/compose-stack.nix  # same, via launchd user agent (OrbStack)
├── stacks/                # Docker compose files (homelab + uptime = deployed; arr-stack = parked)
├── scripts/               # bootstrap.sh + audit helpers
└── docs/                  # Documentation (see NIXOS-INFRA.md for the homelab runbook)
```

## Configuration Flow

### Darwin Systems

1. `flake.nix` calls `libx.mkDarwin { hostname = "mbp"; }`
2. `lib/helpers.nix:mkDarwin` creates the system with:
   - Machine metadata from `lib/machines.nix` (username comes from the
     registry entry, default `hodgesd`; hostname is injected from the attr key)
   - Common packages from `hosts/common/common-packages.nix`
   - Darwin common config from `hosts/common/darwin-common.nix`
   - Host-specific config from `hosts/darwin/<hostname>/default.nix`
     (optional — skipped when the directory doesn't exist)
3. `darwin-common.nix` imports modular configurations:
   - `darwin/base.nix` - Core Nix settings
   - `darwin/homebrew.nix` - Homebrew apps
   - `darwin/system-defaults.nix` - macOS defaults (imports defaults/*)
   - `darwin/fonts.nix` - Fonts
   - `darwin/packages.nix` - Darwin-only packages
4. Home Manager is configured via `home/default.nix`

### NixOS Systems

1. `flake.nix` calls `libx.mkNixos { hostname = "nixos-infra"; }`
2. `lib/helpers.nix:mkNixos` creates the system with:
   - Machine metadata from `lib/machines.nix` (same specialArgs as mkDarwin)
   - Common packages from `hosts/common/common-packages.nix`
   - Server baseline from `hosts/common/nixos-common.nix` (tailscale,
     docker, ssh, firewall, Cachix, compose-stack module)
   - Host config from `hosts/nixos/<hostname>/` (**required** — carries
     hardware-configuration.nix)
   - sops-nix (secrets decrypt at activation)
   - Home Manager only when `withHomeManager = true` (off for servers)

## Key Design Principles

1. **Modularity** - Each concern is in its own file
2. **Reusability** - Common config shared across machines
3. **Machine Metadata** - All machines defined in `lib/machines.nix`
4. **DRY** - Don't Repeat Yourself - use presets and shared configs

## Finding Things

- **Add a package?** → `hosts/common/common-packages.nix` (cross-platform core,
  or the darwin-only block for heavy tooling) or `hosts/common/darwin/packages.nix` (Darwin-only)
- **Change Homebrew apps?** → `hosts/common/darwin/homebrew.nix`
- **Modify dock?** → `hosts/common/darwin/defaults/dock.nix` or host-specific `default.nix`
- **Adjust Finder settings?** → `hosts/common/darwin/defaults/finder.nix`
- **Change keyboard shortcuts?** → `hosts/common/darwin/desktop/skhd.nix`
- **Change a homelab service?** → `hosts/nixos/nixos-infra/*.nix`
- **Edit secrets?** → `sops secrets/nixos-infra.yaml`
- **Add a new machine?** → See `docs/ADDING_MACHINE.md`

## Building

```bash
# Macs: build + switch current host
just

# Macs: build only
just build

# NixOS: dry-run / deploy from the Mac
just deploy-check
just deploy

# Update flake inputs
just update

# Format nix files
nix fmt
```
