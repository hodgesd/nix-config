# Host-specific configuration for mini (M2 Pro desktop, primaryUse = "server").
#
# The mini hosts Uptime Kuma, moved here from nixos-infra so the monitor
# stops sharing a fate with its primary target. That makes this an
# unattended box: everything below exists so it comes back on its own
# after a reboot or a power cut, with nobody at the keyboard.
{username, ...}: {
  # Uptime Kuma + its Tailscale sidecar. stacks/uptime/docker-compose.yml is
  # authoritative; see modules/darwin/compose-stack.nix for the contract.
  # stateDir is under the user's home because OrbStack's docker socket is
  # user-owned, so the reconcile agent runs as this user and needs write
  # access to the bind-mount roots.
  #
  # No envFile: the sidecar's identity comes from the migrated ts-uptime
  # state dir, not an authkey. The compose file defaults TS_AUTHKEY to empty
  # for exactly this reason. If the node key ever expires and the sidecar
  # needs to re-register, mint a key and point envFile at a sops secret.
  majordouble.composeStacks.uptime = {
    composeFile = ../../../stacks/uptime/docker-compose.yml;
    stateDir = "/Users/${username}/srv/uptime";
  };

  # NO auto-login here, deliberately. The compose module generates a *user*
  # LaunchAgent (the docker socket is user-owned), so the stack only starts
  # once a GUI session exists — and FileVault is on, which means macOS gates
  # boot at the pre-boot unlock screen and ignores
  # system.defaults.loginwindow.autoLoginUser entirely. Setting it would
  # imply reboots are handled when they are not.
  #
  # Consequence, worth knowing before you reboot this box:
  #   - Planned reboots: `sudo fdesetup authrestart` pre-authorizes the
  #     unlock, so the mini comes back to a live session unattended.
  #   - Unexpected power cut: it stops at the unlock screen and monitoring
  #     stays down until someone types the password. kuma-watchdog.nix on
  #     nixos-infra is what tells you that has happened.

  # Come back by itself after a power cut or a panic (to the unlock screen,
  # per above), and never sleep out from under the monitors.
  power = {
    restartAfterPowerFailure = true;
    restartAfterFreeze = true;
    sleep = {
      computer = "never";
      display = 30;
      harddisk = "never";
    };
  };
}
