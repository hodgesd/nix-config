# modules/wallpaper.nix
# Home Manager module for macOS wallpaper management using desktoppr
# https://github.com/scriptingosx/desktoppr
{
  config,
  lib,
  pkgs,
  wallpaper ? null,
  ...
}: lib.mkIf (wallpaper != null && wallpaper.enable) {
  # Set wallpaper during home-manager activation
  home.activation.setWallpaper = lib.hm.dag.entryAfter ["writeBoundary"] ''
    echo "Setting wallpaper to ${wallpaper.path}..."
    WP_PATH="${wallpaper.path}"
    
    if [ ! -e "$WP_PATH" ]; then
      echo "Warning: Wallpaper path not found: $WP_PATH"
      echo "Skipping wallpaper setup."
    elif [ -x "/usr/local/bin/desktoppr" ]; then
      # desktoppr is installed - set the wallpaper
      echo "Setting wallpaper with desktoppr..."
      $DRY_RUN_CMD /usr/local/bin/desktoppr "$WP_PATH"
      echo "Wallpaper set successfully."
    else
      echo "Warning: desktoppr not found at /usr/local/bin/desktoppr"
      echo "Install it with: brew install --cask desktoppr"
      echo "Or run 'just switch' to install via Homebrew"
    fi
  '';
}

