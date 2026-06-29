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
    ./darwin/wallpaper.nix
    ./darwin/desktop
  ];

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-darwin";

  home-manager.backupFileExtension = lib.mkForce "hm-backup";

  # Share SwiftBar module with home-manager
  home-manager.sharedModules = [../../modules/swiftbar.nix];
}
