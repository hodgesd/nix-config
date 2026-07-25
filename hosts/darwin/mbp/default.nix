# Host-specific configuration for mbp (M3 Pro Laptop)
# Laptop power/menu-bar defaults are shared via hosts/common/darwin/laptop-defaults.nix
{pkgs, ...}: {
  # Enable wallpaper management
  majordouble.wallpaper = {
    enable = true;
    path = "/Users/hodgesd/Documents/Wallpapers/Gulfstream GV at Waimea.jpg";
  };

  # Tailscale GUI app (network extension + menu bar). The nixpkgs
  # services.tailscale daemon is headless-only; the app is the supported
  # path on macOS. enable/onActivation live in common/darwin/homebrew.nix.
  homebrew.casks = ["tailscale-app"];

  # The cask doesn't link the CLI into PATH; wrap the app's binary.
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "tailscale" ''
      export TAILSCALE_BE_CLI=1
      exec /Applications/Tailscale.app/Contents/MacOS/Tailscale "$@"
    '')
  ];
}
