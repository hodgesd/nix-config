# hosts/common/darwin/desktop/default.nix
# Desktop environment and GUI application configurations
{...}: {
  imports = [
    ./karabiner.nix
    ./skhd.nix
    ./aerospace.nix
    ./swiftbar.nix
  ];
}
