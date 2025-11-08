# Adding a New Machine

This guide walks through adding a new machine to your Nix configuration.

## Step 1: Add Machine Metadata

Edit `lib/machines.nix` and add your machine's metadata:

```nix
# lib/machines.nix
{
  # ... existing machines ...

  newmachine = {
    hostname = "newmachine";
    type = "darwin";  # or "nixos"
    chip = "m4-pro";  # CPU/chip type
    formFactor = "laptop";  # "laptop", "desktop", or "server"
    primaryUse = "development";  # "development", "server", "workstation", etc.
    specs = {
      ram = "32GB";
      storage = "2TB";
      cpu = 14;
      gpu = 20;
    };
    screen = "16\"";  # Optional, for laptops
  };
}
```

## Step 2: Create Host Directory

### For Darwin (macOS):

```bash
mkdir -p hosts/darwin/newmachine
```

Create `hosts/darwin/newmachine/default.nix`:

```nix
{ ... }:
let
  dockPresets = import ../../common/darwin/dock-presets.nix;
in
{
  # Choose a dock preset or define your own
  system.defaults.dock.persistent-apps = dockPresets.developer;

  # Add any machine-specific configuration here
  # For example:
  # homebrew.casks = [ "specific-app" ];
}
```

### For NixOS:

```bash
mkdir -p hosts/nixos/newmachine
```

Create `hosts/nixos/newmachine/default.nix`:

```nix
{ config, pkgs, ... }:
{
  # Machine-specific NixOS configuration
  # Example:
  # services.openssh.enable = true;
}
```

## Step 3: Add to flake.nix

Edit `flake.nix` and add your machine to the appropriate section:

### For Darwin:

```nix
# flake.nix
darwinConfigurations = {
  mbp = libx.mkDarwin {hostname = "mbp";};
  mini = libx.mkDarwin {hostname = "mini";};
  air = libx.mkDarwin {hostname = "air";};
  newmachine = libx.mkDarwin {hostname = "newmachine";};  # Add this
};
```

### For NixOS:

```nix
# flake.nix
nixosConfigurations = {
  desktop = libx.mkNixos {hostname = "desktop";};
  newmachine = libx.mkNixos {hostname = "newmachine";};  # Add this
};
```

## Step 4: Set Machine Hostname

Before building, ensure your machine's hostname matches:

### macOS:

```bash
# Check current hostname
hostname -s

# Set hostname if needed
sudo scutil --set HostName newmachine
sudo scutil --set LocalHostName newmachine
sudo scutil --set ComputerName newmachine
```

Or use the provided script:

```bash
chmod +x set_mac_name.sh
./set_mac_name.sh
```

### NixOS:

The hostname will be set automatically from your configuration.

## Step 5: Build Configuration

```bash
# Check configuration is valid
nix flake check --no-build

# Build and activate (Darwin)
darwin-rebuild switch --flake .#newmachine

# Build and activate (NixOS)
sudo nixos-rebuild switch --flake .#newmachine
```

## Step 6: Customize

Now you can customize your machine-specific configuration:

- **Dock apps**: Edit `hosts/darwin/newmachine/default.nix`
- **Machine-specific packages**: Add to host's `default.nix`
- **Different system settings**: Override in host's `default.nix`

## Common Customizations

### Custom Dock Configuration

Instead of using a preset, define your own:

```nix
# hosts/darwin/newmachine/default.nix
{ ... }:
{
  system.defaults.dock.persistent-apps = [
    "/Applications/Safari.app"
    "/Applications/Mail.app"
    "/Applications/Obsidian.app"
  ];
}
```

### Machine-Specific Homebrew Apps

```nix
# hosts/darwin/newmachine/default.nix
{ ... }:
{
  homebrew.casks = [
    "machine-specific-app"
  ];
}
```

### Different System Defaults

```nix
# hosts/darwin/newmachine/default.nix
{ ... }:
{
  # Override common settings
  system.defaults.dock.autohide = true;
  system.defaults.dock.tilesize = 48;
}
```

### Use Machine Metadata

You can access machine metadata in your config:

```nix
# hosts/darwin/newmachine/default.nix
{ machine, pkgs, ... }:
{
  # Conditional based on machine properties
  environment.systemPackages = with pkgs;
    if machine.formFactor == "laptop" then
      [ powertop ]
    else
      [ ];
}
```

## Updating README

Don't forget to update `README.md` with your new machine's details:

```markdown
## Machines

| Hostname | Model | Storage (Ram/HD) | Cores (CPU/GPU) |
|----------|-------|------------------|-----------------|
| `newmachine` | MacBook Pro M4 Pro 16" | 32GB / 2TB | 14 / 20 |
```

## Troubleshooting

### Configuration doesn't build

```bash
# Check for syntax errors
nix flake check

# Build with verbose output
darwin-rebuild switch --flake .#newmachine --show-trace
```

### Hostname mismatch

Ensure the hostname in:
1. `lib/machines.nix` (hostname field)
2. System hostname (`hostname -s`)
3. `flake.nix` (configuration name)

All match exactly.

### Missing packages

If packages are missing, check:
1. `hosts/common/common-packages.nix` - Cross-platform packages
2. `hosts/common/darwin/packages.nix` - Darwin-specific packages
3. Host-specific `default.nix` - Machine-specific packages
