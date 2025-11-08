{ config, lib, pkgs, ... }:

{
  services.skhd.enable = true;

  home-manager.users.hodgesd = {
    home.file.".skhdrc".text = ''
      hyper - s : open -a "Safari"
      hyper - d : open -a "Drafts"
      hyper - c : open -a "ChatGPT"
      hyper - t : open -a "Warp"
      hyper - o : open -a "Obsidian"
      hyper - p : open -a "PyCharm"
      hyper - f : open -a "Finder"
      hyper - m : open -b com.apple.MobileSMS

      # Safari web apps
      # hyper - e : open -b com.apple.Safari.WebApp.6C8E09D1-46FD-4C8D-A150-DDF60FBBB46C  # hey.com

      # Focus or open Hey web app in Vivaldi
      hyper - e : osascript -e '
        tell application "Vivaldi"
          set found to false
          repeat with w in windows
            if URL of active tab of w is "https://app.hey.com" then
              set index of w to 1
              set found to true
              exit repeat
            end if
          end repeat
          if not found then
            do shell script "/Applications/Vivaldi.app/Contents/MacOS/Vivaldi --app=\"https://app.hey.com\""
          end if
          activate
        end tell'

      # Open Vivaldi in a private window
      hyper - x : open -a "Vivaldi" --args --incognito
    '';
  };
}
