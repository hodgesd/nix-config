# Configuration Structure

This document explains the organization of this Nix configuration.

## Directory Layout

```
nix-config/
├── flake.nix              # Main flake file - defines all systems
├── lib/                   # Library functions and machine metadata
│   ├── default.nix        # Exports helper functions
│   ├── helpers.nix        # mkDarwin function
│   └── machines.nix       # Machine metadata registry
├── hosts/                 # Host-specific configurations
│   ├── common/            # Shared configurations
│   │   ├── common-packages.nix      # Shared package set
│   │   ├── darwin-common.nix        # Darwin entry point
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
│   └── darwin/            # Darwin hosts
│       ├── mbp/
│       │   └── default.nix
│       ├── mini/
│       │   └── default.nix
│       └── air/
│           └── default.nix
├── home/                  # Home Manager configurations
│   ├── default.nix        # User configuration entry point
│   └── modules/           # Tool configs (core, cli, services)
└── modules/               # Custom Home Manager / nix-darwin modules
    ├── swiftbar.nix
    └── wallpaper.nix
```

## Configuration Flow

### Darwin Systems

1. `flake.nix` calls `lib.mkDarwin { hostname = "mbp"; }`
2. `lib/helpers.nix:mkDarwin` creates the system with:
   - Machine metadata from `lib/machines.nix`
   - Common packages from `hosts/common/common-packages.nix`
   - Darwin common config from `hosts/common/darwin-common.nix`
   - Host-specific config from `hosts/darwin/mbp/default.nix`
3. `darwin-common.nix` imports modular configurations:
   - `darwin/base.nix` - Core Nix settings
   - `darwin/homebrew.nix` - Homebrew apps
   - `darwin/system-defaults.nix` - macOS defaults (imports defaults/*)
   - `darwin/fonts.nix` - Fonts
   - `darwin/packages.nix` - Darwin-only packages
4. Home Manager is configured via `home/default.nix`

## Key Design Principles

1. **Modularity** - Each concern is in its own file
2. **Reusability** - Common config shared across machines
3. **Machine Metadata** - All machines defined in `lib/machines.nix`
4. **DRY** - Don't Repeat Yourself - use presets and shared configs

## Finding Things

- **Add a package?** → `hosts/common/common-packages.nix` (cross-platform) or `hosts/common/darwin/packages.nix` (Darwin-only)
- **Change Homebrew apps?** → `hosts/common/darwin/homebrew.nix`
- **Modify dock?** → `hosts/common/darwin/defaults/dock.nix` or host-specific `default.nix`
- **Adjust Finder settings?** → `hosts/common/darwin/defaults/finder.nix`
- **Change keyboard shortcuts?** → `hosts/common/darwin/skhd.nix`
- **Add a new machine?** → See `docs/ADDING_MACHINE.md`

## Building

```bash
# Build current system
darwin-rebuild switch --flake .

# Build specific host
darwin-rebuild switch --flake .#mbp

# Check configuration without building
nix flake check --no-build

# Update flake inputs
nix flake update
```
