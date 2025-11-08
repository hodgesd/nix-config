# Managing Homebrew Packages

This guide covers managing Homebrew casks and Mac App Store apps in your Nix configuration.

## Overview

Homebrew configuration is managed in `hosts/common/darwin/homebrew.nix` using the `nix-homebrew` integration. This provides declarative management of:
- Homebrew casks (GUI applications)
- Mac App Store apps
- Homebrew formulas (brews)
- Homebrew taps

## Adding Applications

### Adding a Homebrew Cask

Edit `hosts/common/darwin/homebrew.nix`:

```nix
casks = [
  # ... existing casks ...
  "your-new-app"
];
```

Then rebuild:

```bash
darwin-rebuild switch --flake .
```

### Adding a Mac App Store App

1. Find the app ID from the Mac App Store URL or using:

```bash
# Search for app
mas search "app name"
```

2. Add to `hosts/common/darwin/homebrew.nix`:

```nix
masApps = {
  # ... existing apps ...
  "Your App Name" = 123456789;  # Use the ID from mas search
};
```

### Adding a Homebrew Formula (brew)

For command-line tools, prefer Nix packages in `hosts/common/common-packages.nix`. If you must use Homebrew:

```nix
brews = [
  "your-cli-tool"
];
```

### Adding a Custom Tap

```nix
taps = [
  "username/tap-name"
];
```

## Removing Applications

Simply remove the entry from the appropriate list and rebuild. With `cleanup = "zap"` enabled (default), Homebrew will automatically uninstall removed apps.

## Organization

The current homebrew.nix organizes apps by category:

```nix
casks = [
  # --- Mac Utilities ---
  "raycast"
  "rectangle"

  # --- Developer & Power Tools ---
  "ghostty"
  "warp"

  # --- Communication & Productivity ---
  "discord"
  "obsidian"

  # --- Browsers ---
  "brave-browser"
  "vivaldi"

  # --- Media & Gaming ---
  "steam"
  "whisky"

  # --- Virtualization / System Management ---
  "orbstack"
  "balenaetcher"
];
```

Maintain this organization when adding new apps.

## Machine-Specific Apps

To install apps only on specific machines:

### Option 1: In Host Configuration

```nix
# hosts/darwin/mbp/default.nix
{ ... }:
{
  homebrew.casks = [
    "machine-specific-app"
  ];
}
```

### Option 2: Using Machine Metadata

```nix
# hosts/common/darwin/homebrew.nix
{ lib, machine, ... }:
{
  homebrew.casks = [
    # Common apps
    "raycast"
    "obsidian"
  ] ++ lib.optionals (machine.primaryUse == "development") [
    # Development-only apps
    "ghostty"
    "warp"
  ] ++ lib.optionals (machine.formFactor != "server") [
    # GUI apps (not on servers)
    "firefox"
    "chrome"
  ];
}
```

## Configuration Options

Current settings in `homebrew.nix`:

```nix
homebrew = {
  enable = true;
  onActivation = {
    cleanup = "zap";      # Uninstall removed apps
    autoUpdate = true;    # Update Homebrew on activation
    upgrade = true;       # Upgrade installed apps
  };
  global.autoUpdate = true;
};
```

### Available Options

- `cleanup = "zap"` - Aggressively remove apps and dependencies
- `cleanup = "uninstall"` - Remove apps but keep dependencies
- `cleanup = "none"` - Don't remove anything
- `autoUpdate = true/false` - Update Homebrew itself
- `upgrade = true/false` - Upgrade installed packages

## Finding Cask Names

### Search Homebrew

```bash
brew search "app name"
```

### Online

Visit [https://formulae.brew.sh/cask/](https://formulae.brew.sh/cask/)

## Troubleshooting

### App won't install

Check if it exists:
```bash
brew info --cask app-name
```

### App requires tap

Some apps need a tap to be added first:
```nix
taps = [
  "homebrew/cask-versions"  # For beta/nightly versions
];
```

### Cleanup issues

If cleanup fails, you can manually remove apps:
```bash
brew uninstall --cask app-name
```

### Forcing reinstall

```bash
# Remove Homebrew cache
rm -rf ~/Library/Caches/Homebrew/*

# Rebuild
darwin-rebuild switch --flake .
```

## Best Practices

1. **Prefer Nix packages** - Use Nix packages when available (in `common-packages.nix`)
2. **Use casks for GUI apps** - Reserve Homebrew for GUI applications that aren't in nixpkgs
3. **Keep organized** - Maintain category comments for clarity
4. **Document custom taps** - Add comments explaining why custom taps are needed
5. **Test on one machine first** - Before adding to common config, test on one machine

## Examples

### Adding VS Code

```nix
casks = [
  "visual-studio-code"
];
```

### Adding Multiple Apps

```nix
casks = [
  # ... existing apps ...

  # --- Your New Category ---
  "new-app-1"
  "new-app-2"
  "new-app-3"
];
```

### Conditional Installation

```nix
{ lib, machine, ... }:
{
  homebrew.casks =
    # Base apps everyone gets
    [
      "raycast"
      "obsidian"
    ]
    # Gaming apps only on non-server machines
    ++ lib.optionals (machine.primaryUse != "server") [
      "steam"
      "whisky"
    ]
    # Development tools only on dev machines
    ++ lib.optionals (machine.primaryUse == "development") [
      "visual-studio-code"
      "docker"
    ];
}
```

## Related Files

- `hosts/common/darwin/homebrew.nix` - Main Homebrew configuration
- `hosts/darwin/*/default.nix` - Machine-specific Homebrew additions
- `lib/machines.nix` - Machine metadata for conditional installs
