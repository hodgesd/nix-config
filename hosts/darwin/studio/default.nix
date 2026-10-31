# Host-specific configuration for studio (Mac Studio M5 Ultra, 96GB,
# primaryUse = "server").
#
# Single purpose: local AI inference. Nothing else belongs here —
# nixos-infra stays the monitoring/control plane (it watches this box, never
# the reverse) and the mini keeps the Hermes Apple/vault bridges, which need
# its iCloud session. The phased build-out lives in
# docs/studio/claude-code-prompt.md; this file is Phase 0 (the host exists
# and evaluates). Phase 1 adds the headless baseline, Phase 3/3b the model
# servers.
{...}: {
  # FileVault stays ON, and unlike the mini this host can be recovered
  # remotely: macOS 26+ on Apple silicon runs a limited SSH server at the
  # FileVault pre-boot stage, so the volume unlocks with the local account
  # password (this is why Remote Login is load-bearing here — Phase 1).
  # Worth knowing before you reboot this box:
  #   - Planned reboots: `sudo fdesetup authrestart` pre-authorizes the
  #     unlock, so it returns to a live session unattended.
  #   - Unexpected reboot or power cut: it waits at pre-boot. Unlock over
  #     SSH on the LAN — there is no tailscaled that early, so from away
  #     from home, jump via nixos-infra to studio's reserved LAN IP.
  #     Password auth only; the session drops while the data volume mounts
  #     and macOS finishes booting, then you reconnect.
  #   - That is attended recovery: something still has to authenticate.
  #     Gatus on nixos-infra (Phase 4) is what tells you it needs you.
  #
  # NO auto-login, deliberately: FileVault gates boot before loginwindow
  # ever reads it, so setting it would imply reboots are handled when they
  # are not. Same reasoning as hosts/darwin/mini/default.nix.

  # Come back by itself after a power cut, and never sleep out from under an
  # inference run or a remote build. Display sleep is fine — headless box.
  power = {
    restartAfterPowerFailure = true;
    restartAfterFreeze = true;
    sleep = {
      computer = "never";
      display = 15;
      harddisk = "never";
    };
  };
}
