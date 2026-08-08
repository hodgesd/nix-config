# Tailscale GUI app (network extension + menu bar). The nixpkgs
# services.tailscale daemon is headless-only; the app is the supported
# path on macOS. enable/onActivation live in common/darwin/homebrew.nix.
#
# Shared rather than per-host: every Mac here is a tailnet node, and the
# mini in particular needs the CLI on PATH for its compose stack's
# sidecar and for the reciprocal watchdog to have something to check.
{pkgs, ...}: {
  homebrew.casks = ["tailscale-app"];

  # The cask doesn't link the CLI into PATH; wrap the app's binary.
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "tailscale" ''
      export TAILSCALE_BE_CLI=1
      exec /Applications/Tailscale.app/Contents/MacOS/Tailscale "$@"
    '')
  ];
}
