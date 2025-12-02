# hosts/common/darwin/system-defaults.nix
# macOS system preferences and defaults
# Organized into modular files by category
{...}: {
  imports = [
    ./defaults/general.nix
    ./defaults/keyboard.nix
    ./defaults/finder.nix
    ./defaults/dock.nix
    ./defaults/security.nix
    ./defaults/apps.nix
  ];
}
