# hosts/common/darwin-common.nix
{
  inputs,
  lib,
  ...
}: {
  imports = [
    ./darwin/base.nix
    ./darwin/homebrew.nix
    ./darwin/system-defaults.nix
    ./darwin/fonts.nix
    ./darwin/packages.nix
    ./darwin/laptop-defaults.nix
    ./darwin/tailscale.nix
    # herdr client for the VM agent workbench; workstations only (gated inside)
    ./darwin/agent-workbench-client.nix
    ./darwin/desktop
    # Wallpaper from ~/Documents/Wallpapers on every Mac (opt out per host
    # with majordouble.wallpaper.enable = false).
    ../../modules/wallpaper.nix
  ];

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-darwin";

  home-manager.backupFileExtension = lib.mkForce "hm-backup";

  # Share SwiftBar module with home-manager
  home-manager.sharedModules = [../../modules/swiftbar.nix];
}
