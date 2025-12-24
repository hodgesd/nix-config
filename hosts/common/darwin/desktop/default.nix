# hosts/common/darwin/desktop/default.nix
# Desktop environment and GUI application configurations
{...}: {
  imports = [
    ./karabiner.nix
    ./skhd.nix
    ./jankyborders.nix
    ./swiftbar-config.nix
  ];
}
