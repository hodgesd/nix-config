# Common Customizations

This guide covers common customizations you might want to make to your Nix configuration.

## Table of Contents

- [System Preferences](#system-preferences)
- [Keyboard Shortcuts](#keyboard-shortcuts)
- [Dock Configuration](#dock-configuration)
- [Packages](#packages)
- [Homebrew Apps](#homebrew-apps)
- [Fonts](#fonts)
- [Home Manager](#home-manager)

## System Preferences

System preferences are organized in `hosts/common/darwin/defaults/`:

### Finder Settings

Edit `hosts/common/darwin/defaults/finder.nix`:

```nix
"com.apple.finder" = {
  ShowExternalHardDrivesOnDesktop = true;  # Show external drives on desktop
  ShowPathbar = true;                       # Show path bar
  FXPreferredViewStyle = "Nlsv";           # Default to list view
  # ... more settings
};
```

### Dock Settings

Edit `hosts/common/darwin/defaults/dock.nix`:

```nix
"com.apple.dock" = {
  autohide = false;          # Auto-hide dock
  orientation = "left";      # Dock position: "left", "bottom", "right"
  tilesize = 36;            # Icon size
  minimize-to-application = true;  # Minimize windows into app icon
};
```

### Keyboard Settings

Edit `hosts/common/darwin/defaults/keyboard.nix`:

```nix
NSGlobalDomain.InitialKeyRepeat = 25;  # Delay before key repeat starts
NSGlobalDomain.KeyRepeat = 2;          # Key repeat rate
```

### General macOS Settings

Edit `hosts/common/darwin/defaults/general.nix`:

```nix
NSGlobalDomain.AppleShowAllExtensions = true;  # Show file extensions
NSGlobalDomain.NSAutomaticSpellingCorrectionEnabled = false;  # Disable autocorrect
```

## Keyboard Shortcuts

Keyboard shortcuts are defined in `hosts/common/darwin/skhd.nix`:

### Adding a Shortcut

```nix
home.file.".skhdrc".text = ''
  # Existing shortcuts
  hyper - o : open -a "Obsidian"

  # Your new shortcut
  hyper - b : open -a "Brave Browser"
'';
```

Where `hyper` is typically `cmd + shift + ctrl + opt`.

### Opening Specific URLs

```nix
hyper - g : open "https://github.com"
```

### Running Scripts

```nix
hyper - r : ~/scripts/my-script.sh
```

## Dock Configuration

### Using Presets

Edit your host configuration (`hosts/darwin/mbp/default.nix`):

```nix
let
  dockPresets = import ../../common/darwin/dock-presets.nix;
in
{
  # Use a preset
  system.defaults.dock.persistent-apps = dockPresets.developer;

  # Or use minimal
  # system.defaults.dock.persistent-apps = dockPresets.minimal;
}
```

### Custom Dock Apps

```nix
{
  system.defaults.dock.persistent-apps = [
    "/Applications/Safari.app"
    "/Applications/Mail.app"
    "/Applications/Calendar.app"
    "/Applications/Obsidian.app"
    "/Applications/Ghostty.app"
  ];
}
```

### Creating a New Preset

Edit `hosts/common/darwin/dock-presets.nix`:

```nix
{
  developer = [ ... ];
  minimal = [ ... ];

  # Your new preset
  writer = [
    "/Applications/Obsidian.app"
    "/Applications/Ulysses.app"
    "/Applications/Drafts.app"
  ];
}
```

## Packages

### Adding Cross-Platform Packages

Edit `hosts/common/common-packages.nix`:

```nix
environment.systemPackages = with pkgs; [
  # ... existing packages ...
  your-package-name
];
```

### Adding Darwin-Only Packages

Edit `hosts/common/darwin/packages.nix`:

```nix
environment.systemPackages = with pkgs; [
  # ... existing packages ...
  macos-only-package
];
```

### Adding Machine-Specific Packages

Edit your host's `default.nix` (`hosts/darwin/mbp/default.nix`):

```nix
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    machine-specific-package
  ];
}
```

### Using Unstable Packages

Already configured! Unstable packages are available via `unstablePkgs`:

```nix
# In common-packages.nix
environment.systemPackages = [
  unstablePkgs.bleeding-edge-package
];
```

## Homebrew Apps

See [HOMEBREW.md](./HOMEBREW.md) for detailed information.

Quick add:

```nix
# hosts/common/darwin/homebrew.nix
casks = [
  # ... existing apps ...
  "your-new-app"
];
```

## Fonts

### Adding Fonts

Edit `hosts/common/darwin/fonts.nix`:

```nix
fonts.packages = [
  # ... existing fonts ...
  pkgs.nerd-fonts.meslo-lg
  pkgs.font-awesome
];
```

### Available Nerd Fonts

```nix
pkgs.nerd-fonts.fira-code
pkgs.nerd-fonts.jetbrains-mono
pkgs.nerd-fonts.hack
pkgs.nerd-fonts.meslo-lg
pkgs.nerd-fonts.ubuntu-mono
# ... and many more
```

## Home Manager

Home Manager configuration is in `home/hodgesd.nix` and imported modules.

### Git Configuration

```nix
# home/hodgesd.nix
programs.git = {
  enable = true;
  userEmail = "your@email.com";
  userName = "Your Name";
  extraConfig = {
    init.defaultBranch = "main";
    # ... more config
  };
};
```

### Shell Configuration

```nix
programs.zsh = {
  enable = true;
  shellAliases = {
    ll = "ls -la";
    gs = "git status";
  };
};
```

### Starship Prompt

Configuration in `home/starship/starship.nix` or edit directly:

```nix
programs.starship = {
  enable = true;
  settings = {
    add_newline = false;
    character = {
      success_symbol = "[➜](bold green)";
      error_symbol = "[➜](bold red)";
    };
  };
};
```

## Conditional Configuration

### Based on Machine Type

```nix
{ machine, pkgs, ... }:
{
  environment.systemPackages = with pkgs;
    # Base packages
    [ git vim ]
    # Laptop-specific
    ++ lib.optionals (machine.formFactor == "laptop") [
      powertop
    ]
    # Server-specific
    ++ lib.optionals (machine.formFactor == "server") [
      htop
      tmux
    ];
}
```

### Based on Primary Use

```nix
{ machine, ... }:
{
  homebrew.casks =
    if machine.primaryUse == "development" then
      [ "visual-studio-code" "docker" ]
    else
      [ "safari" ];
}
```

## Tips and Tricks

### Find Package Names

```bash
# Search for a package
nix search nixpkgs package-name

# Search unstable
nix search nixpkgs#nixpkgs-unstable package-name
```

### Find System Defaults

Use:
```bash
# List all defaults
defaults domains

# Read specific domain
defaults read com.apple.dock

# Find a specific setting
defaults find KeyRepeat
```

### Preview Changes

```bash
# Check configuration without building
nix flake check

# Build but don't activate
darwin-rebuild build --flake .

# Dry run to see what would change
darwin-rebuild switch --flake . --dry-run
```

### Rollback

```bash
# List generations
darwin-rebuild --list-generations

# Switch to previous generation
darwin-rebuild switch --rollback

# Switch to specific generation
darwin-rebuild switch --switch-generation 42
```

## Common Scenarios

### I want to change the dock size

Edit `hosts/common/darwin/defaults/dock.nix`:
```nix
tilesize = 48;  # Change from 36 to 48
```

### I want to add a keyboard shortcut

Edit `hosts/common/darwin/skhd.nix`:
```nix
hyper - x : open -a "YourApp"
```

### I want different settings on my laptop vs desktop

Use machine metadata in your configuration:
```nix
{ machine, ... }:
{
  system.defaults.dock.autohide =
    machine.formFactor == "laptop";  # Hide dock on laptops only
}
```

### I want to install an app only on one machine

Edit that machine's `hosts/darwin/MACHINE/default.nix`:
```nix
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    machine-specific-package
  ];
}
```

## Need More Help?

- [Nix Darwin Options](https://daiderd.com/nix-darwin/manual/index.html)
- [Home Manager Options](https://nix-community.github.io/home-manager/options.html)
- [NixOS Package Search](https://search.nixos.org/packages)
- [Homebrew Cask Search](https://formulae.brew.sh/cask/)
