# hosts/common/darwin/wallpaper.nix
# macOS wallpaper rotation configuration
{
  config,
  lib,
  ...
}: let
  # Determine wallpaper path: use configured path or default to /Users/{username}/Documents/Wallpapers
  wallpaperPath =
    if config.majordouble.wallpaper.path != null
    then config.majordouble.wallpaper.path
    else "/Users/${config.majordouble.user}/Documents/Wallpapers";
  
  wallpaperConfig = {
    enable = config.majordouble.wallpaper.enable;
    path = wallpaperPath;
    changeInterval = config.majordouble.wallpaper.changeInterval;
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

