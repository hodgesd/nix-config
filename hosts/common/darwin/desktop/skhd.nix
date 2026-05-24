{
  config,
  lib,
  pkgs,
  ...
}: {
  # This configuration uses jackielii/tap/my-skhd (jackielii's C skhd fork).
  # The brew is installed via homebrew.nix; the LaunchAgent is registered via
  # skhd's own `--start-service` mechanism in `startSkhd` below. (my-skhd
  # doesn't implement brew's #service DSL, so `start_service = true` is
  # incompatible with `brew bundle`.)

  # Disable the default skhd service to avoid conflict with the brew-managed one.
  services.skhd.enable = false;

  home-manager.users.${config.majordouble.user} = {
    # First-time bootstrap: register skhd's LaunchAgent via its own command.
    # Idempotent across rebuilds: skips if a skhd launchd job is already loaded.
    home.activation.startSkhd = ''
      if ! /bin/launchctl list 2>/dev/null | grep -q skhd; then
        run /opt/homebrew/bin/skhd --start-service \
          || echo "skhd --start-service failed (run it manually if needed)"
      fi
    '';

    # Reload skhd after configuration changes
    home.activation.reloadSkhd = ''
      run /opt/homebrew/bin/skhd -r || echo "skhd reload failed (this is normal if skhd isn't running yet)"
    '';

    # skhd reads ~/.config/skhd/skhdrc before ~/.skhdrc
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
