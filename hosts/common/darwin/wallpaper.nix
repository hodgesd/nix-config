# hosts/common/darwin/wallpaper.nix
# macOS wallpaper rotation configuration
{
  config,
  ...
}: let
  # Determine wallpaper path: use configured path or default to /Users/{username}/Documents/Wallpapers
  wallpaperPath =
    if config.majordouble.wallpaper.path != null
    then config.majordouble.wallpaper.path
    else "/Users/${config.majordouble.user}/Documents/Wallpapers";
in {
  system.activationScripts.wallpaperRotation = {
    text = ''
      echo "Syncing Wallpaper settings for ${wallpaperPath}..."

      WP_PATH="${wallpaperPath}"

      if [ -d "$WP_PATH" ]; then
        sudo -u ${config.majordouble.user} /usr/bin/osascript <<EOT
          tell application "System Events"
            -- Convert the path to a format macOS automation understands
            set wpFolder to POSIX file "$WP_PATH"
            
            repeat with aDesktop in every desktop
              -- Set the folder for rotation
              set picture folder of aDesktop to wpFolder
              
              -- Set change interval (default: 30 minutes / 1800 seconds)
              set change interval of aDesktop to ${toString config.majordouble.wallpaper.changeInterval}
              
              -- Match the screenshot: Check the 'Randomly' box
              set random order of aDesktop to true
            end repeat
          end tell
EOT
        echo "Wallpaper rotation successfully applied to all screens."
      else
        echo "Warning: $WP_PATH not found. Please ensure the folder exists."
      fi
    '';
  };
}

