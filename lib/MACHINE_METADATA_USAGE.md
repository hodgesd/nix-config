# Machine Metadata Usage

The `lib/machines.nix` file contains metadata for all machines in this configuration.

## Accessing Machine Metadata

Machine metadata is automatically passed to all system configurations via `specialArgs.machine`.

### In Configuration Files

```nix
# Example: hosts/darwin/mbp/default.nix
{ machine, ... }:
{
  # Access machine properties
  # machine.hostname  # "mbp"
  # machine.chip      # "m3-pro"
  # machine.formFactor # "laptop"
  # machine.primaryUse # "development"
  # machine.specs.ram  # "18GB"

  # Example: conditional configuration based on machine type
  environment.systemPackages =
    if machine.primaryUse == "server" then
      [ pkgs.htop pkgs.tmux ]
    else
      [ pkgs.firefox pkgs.vscode ];
}
```

### In Home Manager Configs

The machine metadata is also available in home-manager configurations:

```nix
# Example: home/hodgesd.nix
{ machine, ... }:
{
  # Configure based on machine specs
  programs.starship.settings = {
    hostname.format = "[$hostname (${machine.chip})]($style) ";
  };
}
```

### Available Properties

Each machine has:
- `hostname` - The machine's hostname
- `type` - Either "darwin" or "nixos"
- `chip` - CPU/chip type (e.g., "m3-pro", "m1", "i7-5650u")
- `formFactor` - "laptop", "desktop", or "server"
- `primaryUse` - "development", "server", "workstation", etc.
- `specs` - Object with `ram`, `storage`, `cpu`, `gpu` (may be null)
- `screen` - Screen size for laptops (optional)

## Examples

### Conditional Package Installation

```nix
{ machine, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    git
    vim
  ] ++ (if machine.formFactor == "laptop" then [
    # Laptop-specific packages
    powertop
    acpi
  ] else []);
}
```

### Machine-Specific Settings

```nix
{ machine, ... }:
{
  # Different dock sizes for different machines
  system.defaults.dock.tilesize =
    if machine.formFactor == "desktop" then 48
    else 36;
}
```
