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
    # Reload skhd.zig after configuration changes
    home.activation.reloadSkhd = ''
      run /opt/homebrew/bin/skhd -r || echo "skhd reload failed (this is normal if skhd isn't running yet)"
    '';

    # Use ~/.config/skhd/skhdrc - skhd-zig checks this before ~/.skhdrc
    home.file.".config/skhd/skhdrc".text = ''
      # Meh key (shift + ctrl + alt) shortcuts
      shift + ctrl + alt - a : open -a "ChatGPT"
      shift + ctrl + alt - s : open -a "Safari"
      shift + ctrl + alt - d : open -a "Drafts"
      shift + ctrl + alt - t : open -a "Ghostty"
      shift + ctrl + alt - o : open -a "Obsidian"
      shift + ctrl + alt - p : open -a "PyCharm"
      shift + ctrl + alt - f : open -a "Finder"
      shift + ctrl + alt - m : open -b com.apple.MobileSMS
      shift + ctrl + alt - i : open -b com.apple.systempreferences
      shift + ctrl + alt - y : echo "Meh key works!" | tee ~/skhd-test.log

      shift + ctrl + alt - e : open -a "Fastmail"

      # Open Vivaldi in a private window
      shift + ctrl + alt - x : open -a "Vivaldi" --args --incognito

      # Hyper key (shift + ctrl + alt + cmd) shortcuts
      shift + ctrl + alt + cmd - a : open -a "Cursor"
    '';
  };
}
