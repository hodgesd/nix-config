# lib/options.nix
# Custom options for majordouble's nix configuration
{lib, ...}: {
  options.majordouble = {
    user = lib.mkOption {
      type = lib.types.str;
      default = "hodgesd";
      description = "Primary user name";
    };

    wallpaper = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Select the macOS wallpaper with desktoppr at home-manager activation
          (modules/wallpaper.nix), once per `path`. A directory selects that
          folder as the wallpaper source; a file sets a static picture. macOS
          14+ offers no scriptable way to turn on "Change picture", so the
          rotation toggle and its interval are a one-time step in System
          Settings → Wallpaper after the first switch.
        '';
      };

      path = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Image file or directory of images. Defaults to
          /Users/{username}/Documents/Wallpapers (iCloud-synced).
        '';
      };
    };
  };
}
