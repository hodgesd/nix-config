# modules/wallpaper.nix
# Home Manager module for macOS wallpaper rotation
{
  config,
  lib,
  wallpaper ? null,
  ...
}: lib.mkIf (wallpaper != null) {
  # Use home-manager activation script to set wallpaper (runs as user)
  home.activation.setWallpaper = lib.hm.dag.entryAfter ["writeBoundary"] ''
    echo "Setting up wallpaper rotation for ${wallpaper.path}..."
    WP_PATH="${wallpaper.path}"
    WP_INTERVAL="${toString wallpaper.changeInterval}"
    
    if [ -d "$WP_PATH" ]; then
      echo "Wallpaper directory found: $WP_PATH"
      /usr/bin/osascript <<EOT || true
        tell application "System Events"
          -- Convert the path to a format macOS automation understands
          set wpFolder to POSIX file "$WP_PATH"
          
          repeat with aDesktop in every desktop
            -- Set the folder for rotation
            set picture folder of aDesktop to wpFolder
            
            -- Set change interval (default: 30 minutes / 1800 seconds)
            set change interval of aDesktop to $WP_INTERVAL
            
            -- Match the screenshot: Check the 'Randomly' box
            set random order of aDesktop to true
          end repeat
        end tell
EOT
      echo "Wallpaper rotation configured successfully."
    else
      echo "Warning: Wallpaper directory not found: $WP_PATH"
    fi
  '';
}

