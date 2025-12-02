# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a modular Nix configuration managing both macOS (via nix-darwin) and NixOS systems. The configuration uses a machine metadata system for conditional configurations and follows a highly modular structure.

## Build and Development Commands

### Building Configurations

```bash
# Build and activate current host's configuration
darwin-rebuild switch --flake .

# Build specific host
darwin-rebuild switch --flake .#mbp

# Build without activating
darwin-rebuild build --flake .

# Build with detailed error traces
darwin-rebuild build --flake . --show-trace

# Check configuration validity (no build)
nix flake check

# NixOS systems
nixos-rebuild switch --flake .#hostname
```

### Using Just (recommended)

```bash
# Build and switch (default command)
just

# Build specific host
just switch mbp

# Build with trace output
just trace

# Update flake inputs
just update

# Garbage collect old generations
just gc 5  # Keep last 5 generations
```

### Managing Changes

```bash
# Update all flake inputs
nix flake update

# Rollback to previous generation
darwin-rebuild switch --rollback

# List generations
darwin-rebuild --list-generations

# Preview what would change (dry run)
darwin-rebuild switch --flake . --dry-run
```

## Architecture

### Configuration Flow

**Darwin Systems:**
1. `flake.nix` → calls `lib/helpers.nix:mkDarwin` with hostname
2. `mkDarwin` loads:
   - Machine metadata from `lib/machines.nix`
   - Cross-platform packages from `hosts/common/common-packages.nix`
   - Darwin common config from `hosts/common/darwin-common.nix`
   - Host-specific overrides from `hosts/darwin/{hostname}/default.nix`
3. `darwin-common.nix` imports modular components (base, homebrew, fonts, packages, system-defaults)
4. Home Manager configs from `home/hodgesd.nix`

**NixOS Systems:**
Similar flow using `mkNixos` and `hosts/common/nixos-common.nix`

### Machine Metadata System

All machines are defined in `lib/machines.nix` with metadata like:
- `type`: "darwin" or "nixos"
- `formFactor`: "laptop", "desktop", "server"
- `primaryUse`: "development", "server", "ai-inference", etc.
- `chip`: "m1", "m2-pro", "m3-pro", etc.
- `specs`: ram, storage, cpu, gpu cores

This metadata is available as the `machine` argument in all modules for conditional configuration:

```nix
{ machine, pkgs, ... }:
{
  environment.systemPackages = with pkgs;
    []
    ++ lib.optionals (machine.formFactor == "laptop") [ powertop ]
    ++ lib.optionals (machine.primaryUse == "development") [ docker ];
}
```

### Key Helper Functions

Located in `lib/helpers.nix`:

- `mkDarwin { hostname, username?, system? }` - Creates nix-darwin configurations
- `mkNixos { hostname, username?, system? }` - Creates NixOS configurations

Both functions automatically:
- Load machine metadata
- Import common and host-specific configs
- Set up Home Manager
- Provide `unstablePkgs` for bleeding-edge packages

### Modular Darwin Configuration

Darwin-specific modules in `hosts/common/darwin/`:
- `base.nix` - Core Nix daemon settings, auto-upgrade, garbage collection
- `homebrew.nix` - Homebrew formulae, casks, Mac App Store apps
- `packages.nix` - Darwin-only Nix packages
- `fonts.nix` - Font packages
- `system-defaults.nix` - Imports all defaults/* modules
- `dock-presets.nix` - Reusable Dock configurations
- `skhd.nix` - Keyboard shortcuts via skhd
- `karabiner.nix` - Keyboard remapping
- `defaults/` - macOS system preferences by category:
  - `general.nix` - NSGlobalDomain settings
  - `keyboard.nix` - Keyboard and input settings
  - `finder.nix` - Finder preferences
  - `dock.nix` - Dock behavior
  - `security.nix` - Security and privacy
  - `apps.nix` - Application-specific settings

## Common Modifications

### Adding Packages

**Cross-platform:** Edit `hosts/common/common-packages.nix`
```nix
environment.systemPackages = with pkgs; [
  package-name
];
```

**Darwin-only:** Edit `hosts/common/darwin/packages.nix`

**Unstable package:** Use `unstablePkgs` (already configured):
```nix
environment.systemPackages = [
  unstablePkgs.package-name
];
```

**Machine-specific:** Edit `hosts/darwin/{hostname}/default.nix`

### Homebrew Apps

Edit `hosts/common/darwin/homebrew.nix`:
```nix
casks = [ "app-name" ];           # GUI apps
brews = [ "formula-name" ];       # CLI tools
masApps = { "App Name" = 123; };  # Mac App Store (ID from mas search)
```

### Dock Configuration

**Use preset:** In host config (`hosts/darwin/mbp/default.nix`):
```nix
let
  dockPresets = import ../../common/darwin/dock-presets.nix;
in
{
  system.defaults.dock.persistent-apps = dockPresets.developer;
}
```

**Custom apps:** List app paths directly:
```nix
system.defaults.dock.persistent-apps = [
  "/Applications/Safari.app"
  "/Applications/Ghostty.app"
];
```

**Create new preset:** Edit `hosts/common/darwin/dock-presets.nix`

### System Preferences

All in `hosts/common/darwin/defaults/`:
- Finder behavior: `finder.nix`
- Dock settings: `dock.nix`
- Keyboard settings: `keyboard.nix`
- General macOS: `general.nix`

### Keyboard Shortcuts

Edit `hosts/common/darwin/skhd.nix`:
```nix
home.file.".skhdrc".text = ''
  hyper - o : open -a "Obsidian"
'';
```

## Adding a New Machine

1. Add metadata to `lib/machines.nix`
2. Create host directory: `hosts/darwin/{hostname}/` or `hosts/nixos/{hostname}/`
3. Create `default.nix` with host-specific config
4. Add to `flake.nix` darwinConfigurations or nixosConfigurations
5. Build: `darwin-rebuild switch --flake .#{hostname}`

See `docs/ADDING_MACHINE.md` for detailed steps.

## Formatting

Code is formatted with Alejandra:
```bash
# Format is defined in flake.nix outputs.formatter
nix fmt
```

## Important Patterns

### When modifying system defaults:
- Changes in `defaults/` require rebuild + activation
- Some settings may require logout/restart to take effect
- Use `defaults read com.apple.domain` to discover setting keys

### When changing Homebrew apps:
- Nix manages the Homebrew installation
- Changes to `homebrew.nix` are applied on rebuild
- `autoMigrate = true` migrates existing Homebrew installations
- `mutableTaps = true` allows manual `brew tap` additions

### When working with Home Manager:
- Configs in `home/hodgesd.nix` and imported modules
- Changes require darwin-rebuild (not home-manager switch)
- backupFileExtension set to avoid conflicts

## Testing and Validation

```bash
# Validate without building
nix flake check

# Build without activating
darwin-rebuild build --flake .

# Check for Nix syntax errors
nix-instantiate --parse flake.nix

# Show what would change
darwin-rebuild switch --flake . --dry-run
```

## Flake Inputs

Tracked in `flake.lock`, update with `nix flake update`:
- `nixpkgs` - NixOS 25.05 (stable)
- `nixpkgs-unstable` - Rolling release for latest packages
- `nixpkgs-darwin` - Darwin-specific stable
- `nix-darwin` - macOS system management
- `home-manager` - User environment management
- `nix-homebrew` - Declarative Homebrew
- `swiftbar_plugins` - Custom SwiftBar plugins (non-flake)

## Directory Reference

```
flake.nix                       # Main entry point - defines all systems
lib/
  helpers.nix                   # mkDarwin, mkNixos functions
  machines.nix                  # Machine metadata registry
hosts/
  common/
    common-packages.nix         # Cross-platform packages
    darwin-common.nix           # Darwin entry point
    nixos-common.nix            # NixOS entry point
    darwin/                     # Darwin-specific modules (modular)
  darwin/{hostname}/            # Per-host Darwin configs
  nixos/{hostname}/             # Per-host NixOS configs
home/
  hodgesd.nix                   # User config entry point
  {tool}/                       # Tool-specific configs (aerospace, nvim, etc.)
modules/                        # Custom reusable modules
docs/                           # Documentation
  STRUCTURE.md                  # Detailed directory layout
  ADDING_MACHINE.md             # New machine guide
  CUSTOMIZATION.md              # Common customization tasks
  HOMEBREW.md                   # Homebrew management
```
