# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a modular Nix flake managing macOS systems via nix-darwin **and** NixOS
homelab hosts from one lockfile. A machine metadata system
(`lib/machines.nix`) drives conditional configuration. The NixOS side currently
has one host: `nixos-infra`, a Proxmox VM (see `docs/NIXOS-INFRA.md` for its
architecture and disaster-recovery runbook).

## Build and Development Commands

### Using Just (preferred)

```bash
# Macs: build and switch current host (default recipe)
just

# Macs: build only, no activation
just build            # or: just build mbp

# Macs: build with --show-trace
just trace

# NixOS: dry-run / deploy nixos-infra from the Mac
just deploy-check
just deploy

# Update flake inputs
just update

# Garbage collect system generations older than N days (default 14)
just gc
```

### Raw commands

```bash
# Build and activate current host's darwin configuration
darwin-rebuild switch --flake .

# Build without activating
darwin-rebuild build --flake .

# Evaluate any host without building (what CI does)
nix eval --raw ".#darwinConfigurations.mbp.system.drvPath"
nix eval --raw ".#nixosConfigurations.nixos-infra.config.system.build.toplevel.drvPath"

# Rollback (macOS / NixOS)
darwin-rebuild switch --rollback
sudo nixos-rebuild switch --rollback   # on the NixOS host
```

Do NOT deploy NixOS hosts with `nix run nixpkgs#nixos-rebuild` — the registry
nixpkgs is unpinned and its `nixos-rebuild-ng` has a broken macOS wrapper. The
`just deploy` recipe does the pipeline explicitly (eval → copy drvs → remote
realise → activate in a systemd-run unit).

## Architecture

### Configuration Flow

**Darwin:** `flake.nix` → `libx.mkDarwin {hostname}` (`lib/helpers.nix`) →
machine metadata from `lib/machines.nix` + `hosts/common/common-packages.nix` +
`hosts/common/darwin-common.nix` (which imports the modular
`hosts/common/darwin/*` set) + optional `hosts/darwin/<hostname>/default.nix` +
Home Manager (`home/default.nix`).

**NixOS:** `flake.nix` → `libx.mkNixos {hostname}` → same metadata/specialArgs +
`common-packages.nix` + `hosts/common/nixos-common.nix` (server baseline:
tailscale from locked unstable, docker_29, openssh, tailnet-only firewall,
Cachix substituter, compose-stack module) + **required**
`hosts/nixos/<hostname>/` (carries hardware-configuration.nix) + sops-nix.
Home Manager only with `withHomeManager = true` (off for servers).

Both builders pass `specialArgs = {system inputs username unstablePkgs machine}`
and identical `home-manager.extraSpecialArgs` — keep them in sync if you add an
argument.

### Machine Metadata System

Machines are defined in `lib/machines.nix`. The hostname comes from the
attribute name (injected by the helpers — do not add a `hostname` field).
Schema (enforced by `lib/options.nix`):

- `type`: "darwin" | "nixos"
- `formFactor`: "laptop" | "desktop" | "server" | "vm"
- `primaryUse`: free-form string ("development", "server", "homelab", …)
- `chip`: string or omitted (null for VMs)
- `username`: optional, defaults to "hodgesd"
- `specs`: ram/storage (str|null), cpu/gpu (int|null)

Available as the `machine` arg in all modules (including home-manager):

```nix
{ machine, pkgs, lib, ... }:
{
  environment.systemPackages = with pkgs;
    []
    ++ lib.optionals (machine.formFactor == "laptop") [ powertop ]
    ++ lib.optionals (machine.type == "darwin") [ heavy-dev-tool ];
}
```

### Secrets (sops-nix)

Encrypted in `secrets/nixos-infra.yaml`; recipients in `.sops.yaml` (Mac age
key at `~/.config/sops/age/keys.txt` + the VM's SSH host key). Edit with
`sops secrets/nixos-infra.yaml`, deploy with `just deploy`. Secrets decrypt to
`/run/secrets/` at activation; a decryption failure aborts activation before
services restart. IMPORTANT: new files (including secrets) must be `git add`ed
before `nix eval`/`build` can see them — flakes only see tracked files.

### Docker compose stacks

`majordouble.composeStacks.<name>` exists on both platforms with the same
option surface: `modules/nixos/compose-stack.nix` (systemd oneshot) and
`modules/darwin/compose-stack.nix` (launchd user agent, because macOS
container runtimes expose a user-owned socket). Nix installs the repo's
compose file into the stack dir and runs
`docker compose up -d --remove-orphans` on change. The repo copy is
authoritative and images are pinned by digest. Changing an image string
recreates that container (config-hash change) even if it resolves to the
same image.

Stacks: `stacks/homelab/docker-compose.yml` → `/srv/homelab` on
nixos-infra; `stacks/uptime/docker-compose.yml` → `~/srv/uptime` on the
mini (Uptime Kuma, deliberately not on the host it monitors).

On darwin the runtime is OrbStack, addressed only through the module's
`dockerHost` option. Two macOS-specific traps are handled there and
documented inline: the agent must wait for the runtime's VM at login, and
`~/.docker/config.json` names an out-of-store credential helper that must
be on PATH or image pulls fail.

## Common Modifications

### Adding Packages

**Cross-platform core:** `hosts/common/common-packages.nix` (top list).
Heavyweight dev/media tools belong in the darwin-only block at the bottom
(`lib.optionals (machine.type == "darwin")`) — NixOS servers keep a lean closure.

**Darwin-only:** `hosts/common/darwin/packages.nix`

**Unstable:** use `unstablePkgs.package-name` (available in all modules)

**Machine-specific:** `hosts/darwin/<hostname>/default.nix` or
`hosts/nixos/<hostname>/default.nix`

### Homebrew Apps

Edit `hosts/common/darwin/homebrew.nix`:
```nix
casks = [ "app-name" ];           # GUI apps
brews = [ "formula-name" ];       # CLI tools
masApps = { "App Name" = 123; };  # Mac App Store (ID from mas search)
```

### System Preferences

All in `hosts/common/darwin/defaults/`: `general.nix`, `keyboard.nix`,
`finder.nix`, `dock.nix`, `security.nix`.

### Keyboard Shortcuts

Edit `hosts/common/darwin/desktop/skhd.nix`:
```nix
hyper - o : open -a "Obsidian"
```

### Homelab services

Edit `hosts/nixos/nixos-infra/*.nix` (easy-afd, proxy, backup, storage,
homelab-stack), then `just deploy-check` before `just deploy`.

## Adding a New Machine

See `docs/ADDING_MACHINE.md` — covers both Macs and NixOS hosts (registry
entry → host dir → flake output → CI matrix → secrets recipient → deploy).

## Formatting

Alejandra, via the flake's formatter output:
```bash
nix fmt
```
EXCEPTION: `hosts/nixos/nixos-infra/hardware-configuration.nix` is kept
byte-for-byte as generated on the VM — don't format it.

## Important Patterns

- `system.stateVersion` (NixOS) and HM `home.stateVersion` are pinned
  deliberately — never bump them on existing machines.
- Changes in `darwin/defaults/` require rebuild + activation; some settings
  need logout/restart. Use `defaults read com.apple.domain` to discover keys.
- Homebrew: nix manages the installation; `autoMigrate = true`,
  `mutableTaps = true`, cleanup is `"none"`.
- Home Manager configs live in `home/` and are Linux-portable — anything
  darwin-only must be guarded (`pkgs.stdenv.isDarwin`) or live under
  `hosts/common/darwin/desktop/`. Changes require darwin-rebuild (not
  home-manager switch).
- CI (`.github/workflows/`): eval matrix covers every host; build jobs push
  darwin + nixos closures to Cachix (`hodgesd-nix-config`). Add new hosts to
  the matrices.

## Flake Inputs

Tracked in `flake.lock`, update with `just update`:
- `nixpkgs` — nixos-25.11 (shared by darwin and NixOS)
- `nixpkgs-unstable` — rolling; provides `unstablePkgs` (incl. tailscale on
  the VM — check for MagicDNS regressions before bumping, see NIXOS-INFRA.md)
- `nix-darwin` — nix-darwin-25.11
- `home-manager` — release-25.11
- `nix-homebrew` — declarative Homebrew (carries a patched brew 5.0.12; try
  dropping `lib/patches/brew-cask-api.patch` when brew 5.1.x lands)
- `sops-nix` — secrets
- `swiftbar_plugins` — custom SwiftBar plugins (non-flake)

## Directory Reference

```
flake.nix                       # darwin + nixos configurations, formatter
.sops.yaml                      # sops recipient policy
secrets/                        # encrypted secrets (ciphertext)
lib/
  helpers.nix                   # mkDarwin + mkNixos
  options.nix                   # majordouble.* schema
  machines.nix                  # Machine metadata registry
hosts/
  common/
    common-packages.nix         # Shared package set (+ darwin-only block)
    darwin-common.nix           # Darwin entry point
    nixos-common.nix            # NixOS server baseline
    darwin/                     # Darwin-specific modules (modular)
  darwin/{hostname}/            # Per-host Darwin configs (optional)
  nixos/{hostname}/             # Per-host NixOS configs (required)
home/
  default.nix                   # User config entry point (portable)
  modules/                      # Tool-specific configs (core, cli, services)
modules/                        # Custom modules (swiftbar, wallpaper, {nixos,darwin}/compose-stack)
stacks/                         # Docker compose files (homelab + uptime deployed, arr-stack parked)
scripts/                        # bootstrap.sh + audit helpers
docs/                           # STRUCTURE, ADDING_MACHINE, CUSTOMIZATION,
                                # HOMEBREW, NIXOS-INFRA (homelab runbook)
```
