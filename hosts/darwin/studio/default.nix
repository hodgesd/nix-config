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
{
  username,
  lib,
  ...
}: {
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

  # Three things this box depends on are NOT expressible in nix-darwin
  # 26.05, so they are bootstrap steps recorded in docs/studio/phase-1.md
  # rather than silently omitted:
  #   - Remote Login (SSH). `services.openssh` here only runs ssh-keygen
  #     for host keys — its activation script does nothing else, so
  #     enabling it would not turn Remote Login on. `systemsetup
  #     -setremotelogin on` needs Full Disk Access for the calling
  #     process, which an activation script run over SSH does not have.
  #   - Screen Sharing: same story, and optional here.
  #   - "Start up when power is connected" = Always (System Settings →
  #     Energy; macOS 26.5+). `power.*` only has the three options set
  #     above. This one is strictly better than restartAfterPowerFailure
  #     — it also powers the Mac on from a full shutdown when power
  #     returns — so both are in force: the nix option for what it
  #     covers, the GUI setting for the rest.

  # Check for updates; never install them unattended. An unattended
  # FileVault box that installs an OS update reboots into the pre-boot
  # unlock screen and stays there until someone authenticates — see the
  # recovery ladder above. OS updates are a deliberate
  # `sudo fdesetup authrestart` ritual instead.
  system.defaults.SoftwareUpdate.AutomaticallyInstallMacOSUpdates = false;

  # The rest of the update posture is already right, fleet-wide, from
  # darwin/defaults/security.nix: AutomaticCheckEnabled, AutomaticDownload
  # and CriticalUpdateInstall are on in the user domain. Studio inherits
  # them deliberately — checking and staging never reboot on their own,
  # and CriticalUpdateInstall covers security responses, which are data
  # rather than OS updates. Do not re-declare those here in
  # CustomSystemPreferences: a second copy in the system domain shadows
  # the fleet setting and makes the posture ambiguous.

  # The one fleet default a server must not inherit. App Store apps
  # update in the user domain (the key System Settings reads), and
  # security.nix turns that on for workstations. Off here so a binary
  # never swaps underneath a running service — the same reasoning as
  # homebrew.nix's `upgrade = false`. mkForce because the fleet default
  # is an explicit `true`, not a mkDefault.
  system.defaults.CustomUserPreferences."com.apple.commerce".AutoUpdate = lib.mkForce false;

  # Raise how much unified memory the GPU may wire. macOS defaults to
  # roughly 65–75% of RAM; on this machine's 98,304 MB that strands
  # something like 9–20GB of model headroom. 83,500 MB is ~85%, leaving
  # ~14.5GB for the OS and the serving process itself. (The live value
  # reads 0, which means "unset, use the default" — not "unlimited".)
  #
  # A daemon rather than a one-shot because the sysctl does not survive a
  # reboot, and root rather than a user agent because it must apply
  # before anything loads a model and has nothing to do with a login
  # session. One-line disable: comment this block out and rebuild; the
  # value returns to the macOS default on the next boot.
  launchd.daemons.gpu-wired-limit = {
    serviceConfig = {
      ProgramArguments = ["/usr/sbin/sysctl" "iogpu.wired_limit_mb=83500"];
      RunAtLoad = true;
      # One-shot: it sets a sysctl and exits. KeepAlive would respawn it
      # in a loop forever.
      KeepAlive = false;
      StandardErrorPath = "/var/log/gpu-wired-limit.log";
    };
  };

  system.activationScripts.extraActivation.text = ''
    # Model and cache storage is large and entirely regenerable: never
    # back it up, never index it. Both engines' paths are handled here so
    # Phase 3b does not need a second mechanism —
    #   ~/.ollama             Ollama blobs (Phase 3)
    #   ~/.cache/huggingface  HF-format models oMLX reads (Phase 3b)
    # The directories do not exist on a fresh machine and `tmutil
    # addexclusion` on a missing path does not stick, so create them
    # first — as the user, because root-owned directories under ~ would
    # break the serving agent later. Idempotent.
    for d in "/Users/${username}/.ollama" "/Users/${username}/.cache/huggingface"; do
      /usr/bin/sudo -u ${username} /bin/mkdir -p "$d"
      /usr/bin/sudo -u ${username} /usr/bin/touch "$d/.metadata_never_index"
      /usr/bin/tmutil addexclusion "$d" >/dev/null 2>&1 || true
    done

    # Remote Login is this machine's only remote recovery path: it is the
    # prerequisite for FileVault pre-boot SSH unlock. It cannot be set
    # declaratively (see the comment above), so the real risk is that it
    # drifts off and nobody notices until an outage. Warn loudly, but do
    # NOT fail the rebuild over it.
    if ! /bin/launchctl print system/com.openssh.sshd >/dev/null 2>&1; then
      printf >&2 '\e[1;33mwarning: Remote Login (SSH) is OFF on studio.\e[0m\n'
      printf >&2 '  FileVault pre-boot unlock depends on it, so this box cannot be\n'
      printf >&2 '  recovered remotely until it is back on:\n'
      printf >&2 '    System Settings > General > Sharing > Remote Login\n'
    fi
  '';
}
