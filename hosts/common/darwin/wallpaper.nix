# hosts/common/darwin/wallpaper.nix
# Wires modules/wallpaper.nix (Home Manager) to the majordouble.wallpaper
# options. A folder path means macOS-native rotation; see the module header.
{config, ...}: let
  # Default to the user's iCloud-synced Wallpapers folder.
  wallpaperPath =
    if config.majordouble.wallpaper.path != null
    then config.majordouble.wallpaper.path
    else "/Users/${config.majordouble.user}/Documents/Wallpapers";

  wallpaperConfig = {
    enable = config.majordouble.wallpaper.enable;
    path = wallpaperPath;
  };
in {
  # Add wallpaper module to home-manager sharedModules
  home-manager.sharedModules = [
    ../../../modules/wallpaper.nix
  ];

  # Pass wallpaper config to home-manager via the user's _module.args
  # This makes it available to the wallpaper home-manager module
  home-manager.users.${config.majordouble.user} = {
    _module.args.wallpaper = wallpaperConfig;
  };
}
