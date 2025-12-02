{
  config,
  lib,
  pkgs,
  ...
}: {
  # This configuration uses SKHD.ZIG (the Zig rewrite of skhd).
  # The brew is installed via homebrew.nix with start_service = true

  # Disable the default skhd service to avoid conflict with the Zig version.
  services.skhd.enable = false;

  home-manager.users.${config.majordouble.user} = {
    # The focus-hey.sh script is an external script to avoid AppleScript parsing issues.
    home.file."bin/focus-hey.sh" = {
      text = ''
        #!/bin/bash
        osascript -e "tell application \"Vivaldi\" to activate"
      '';
      executable = true;
    };

    home.file.".skhdrc".text = ''
      # Meh key (shift + ctrl + alt) shortcuts
      shift + ctrl + alt - s : open -a "Safari"
      shift + ctrl + alt - d : open -a "Drafts"
      shift + ctrl + alt - c : open -a "ChatGPT"
      shift + ctrl + alt - t : open -a "Ghostty"
      shift + ctrl + alt - o : open -a "Obsidian"
      shift + ctrl + alt - p : open -a "PyCharm"
      shift + ctrl + alt - f : open -a "Finder"
      shift + ctrl + alt - m : open -b com.apple.MobileSMS
      shift + ctrl + alt - y : echo "Meh key works!" | tee ~/skhd-test.log

      # Focus or open Hey web app in Vivaldi
      shift + ctrl + alt - e : ~/bin/focus-hey.sh

      # Open Vivaldi in a private window
      shift + ctrl + alt - x : open -a "Vivaldi" --args --incognito
    '';
  };
}
