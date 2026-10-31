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
  unstablePkgs,
  ...
}: let
  # Phase 3: Ollama from nixpkgs-unstable. 0.34.3 at our locked rev, well
  # past the 0.19 that added the MLX backend for Apple silicon >= 32GB, so
  # no homebrew fallback is needed. Pinned to one store path and shared by
  # the daemon and the CLI, so `ollama ps` always talks to the server this
  # config started.
  ollama = unstablePkgs.ollama;
  ollamaHome = "/Users/${username}";
in {
  # FileVault is deliberately OFF on this host (decided 2026-10-30), which
  # is the opposite of the mini and worth understanding before changing it.
  #
  # Rationale: the box is physically secure, holds no personal data and no
  # Apple ID, and its whole job is to be available. Apple silicon still
  # encrypts the internal SSD in hardware regardless; FileVault adds
  # password protection of the keys at rest. The trade accepted here is
  # weaker at-rest protection against physical access, in exchange for a
  # machine that boots all the way back on its own.
  #
  # What that buys, and what it costs:
  #   - No pre-boot gate. After a reboot or power cut it boots unattended
  #     to loginwindow; system LaunchDaemons start with nobody logged in.
  #     (The macOS 26+ FileVault-over-SSH unlock path is therefore not in
  #     play here. It would be, if FileVault were ever turned back on.)
  #   - User LaunchAgents still need a login session. So anything that must
  #     survive an unattended reboot is either a system LaunchDaemon, or a
  #     user agent plus auto-login — and auto-login is only an option
  #     *because* FileVault is off. Phase 3 picks between those on evidence;
  #     see docs/studio/phase-3.md.
  #   - Nothing about this makes the Mac unattended-proof: Gatus on
  #     nixos-infra (Phase 4) is still what tells you it went away.
  #
  # Remote Login remains load-bearing — it is how this box is administered
  # headlessly over the tailnet — just no longer for pre-boot unlock.

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

  # Key-based SSH from the t3-code VM, so config work and read-only
  # verification can be driven over the tailnet instead of at this
  # machine's keyboard. Declared rather than appended to
  # ~/.ssh/authorized_keys by hand so it survives a from-scratch rebuild
  # and is reviewable in git — the same reasoning that puts the LAN key in
  # nixos-common.nix. Public keys only; nothing here is secret.
  #
  # nix-darwin serves these through sshd's AuthorizedKeysCommand
  # (/etc/ssh/nix_authorized_keys.d/%u), which is ADDITIVE: it does not
  # replace or disturb anything already in ~/.ssh/authorized_keys.
  #
  # This adds no network surface — Remote Login is already on and already
  # tailnet-reachable. It authorizes one more key. One-line disable:
  # delete the entry and rebuild.
  users.users.${username}.openssh.authorizedKeys.keys = [
    # t3-code (Proxmox VM), `agent` user — the box this repo is edited from.
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICqtGYhL9lNLBifxD6zjgV89isCQacI54IKFIgj8dxTA t3-code-agent"
  ];

  # Check for updates; never install them unattended. A self-installing
  # OS update reboots the box out from under an inference run or a remote
  # build, and — depending on how Phase 3 launches the serving stack —
  # may leave it not serving until someone logs in. Updates here are a
  # deliberate, scheduled act.
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

  # The `ollama` CLI on PATH for `pull` / `ps` / `run`. Same store path the
  # daemon runs, so the CLI can never end up talking to a different build.
  environment.systemPackages = [ollama];

  # Ollama, reachable on the tailnet at https://studio.<tailnet>:11434
  # after the one-time (state, not Nix — same as the mini's bridges):
  #     tailscale serve --bg --https=11434 http://127.0.0.1:11434
  #
  # A system DAEMON, not a user agent, and that is the whole point: with
  # FileVault off this box boots to loginwindow by itself, and a daemon
  # starts there with nobody logged in — so an unattended reboot comes back
  # serving. `launchd.user.agents` (the mini's pattern) would wait for a
  # login session. The alternative that would make agents work, auto-login,
  # trades an always-unlocked desktop for nothing we need here.
  #
  # UserName = the login user rather than root: least privilege, and it
  # keeps the model store in ~ where the Phase 1 Time Machine and Spotlight
  # exclusions already point. That works precisely because FileVault is off
  # — the data volume is never gated, so a pre-login daemon can read ~.
  #
  # One-line disable: comment out this block and rebuild, then
  # `tailscale serve --https=11434 off` to retract the tailnet route.
  launchd.daemons.ollama = {
    serviceConfig = {
      ProgramArguments = ["${ollama}/bin/ollama" "serve"];
      UserName = username;
      RunAtLoad = true;
      KeepAlive = true;
      ThrottleInterval = 15;
      # Keep launchd from throttling a long-running inference server.
      ProcessType = "Interactive";
      StandardOutPath = "${ollamaHome}/Library/Logs/ollama.log";
      StandardErrorPath = "${ollamaHome}/Library/Logs/ollama.log";
      EnvironmentVariables = {
        # Loopback ONLY. Ollama has no authentication and its API can pull,
        # delete and run models, so it must never bind a routable address;
        # the tailnet reaches it through `tailscale serve` above.
        OLLAMA_HOST = "127.0.0.1:11434";

        # HOME is NOT inherited by a LaunchDaemon just because UserName is
        # set — it would be unset or `/`, and Ollama would quietly choose a
        # models directory outside ~/.ollama, i.e. outside the Phase 1
        # backup/Spotlight exclusions, with nothing visibly broken. Both of
        # these are set deliberately; do not "simplify" them away.
        HOME = ollamaHome;
        OLLAMA_MODELS = "${ollamaHome}/.ollama/models";

        # 96GB is the reason this machine exists: keep models resident
        # rather than paying the load cost on every request.
        OLLAMA_KEEP_ALIVE = "30m";
        OLLAMA_MAX_LOADED_MODELS = "2";
      };
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

    # Remote Login is how this keyboard-less box is administered at all,
    # and it is what the authorized key above is for. It cannot be set
    # declaratively (see the comment near the top), so the real risk is
    # that it drifts off and nobody notices until they need to get in.
    # Warn loudly, but do NOT fail the rebuild over it.
    if ! /bin/launchctl print system/com.openssh.sshd >/dev/null 2>&1; then
      printf >&2 '\e[1;33mwarning: Remote Login (SSH) is OFF on studio.\e[0m\n'
      printf >&2 '  This box is headless — SSH is the only way in. Re-enable at:\n'
      printf >&2 '    System Settings > General > Sharing > Remote Login\n'
    fi
  '';
}
