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
  # Phase 3: Ollama from nixpkgs-unstable. 0.34.3 at our locked rev.
  ollamaBase = unstablePkgs.ollama;

  # Phase 3: the MLX runtime, which nixpkgs cannot build.
  #
  # Ollama ships two engines: llama.cpp (GGUF) and MLX, picked per model by
  # tag. The MLX code IS compiled into the nixpkgs binary — it dlopens the
  # runtime at startup — but the runtime itself is absent, so every MLX tag
  # fails with "this model requires MLX support, but the MLX runtime is not
  # available".
  #
  # It is absent because it cannot be built here: mlx.metallib is ~190MB of
  # precompiled Metal shaders, and compiling Metal needs Apple's `metal`
  # tool, which ships only with full Xcode and is unavailable to a nix
  # build. (Same wall oMLX documents: `xcrun: unable to find utility
  # "metal"`. It is a nix-on-macOS limit, not a packaging oversight.)
  #
  # So take the prebuilt artifacts from upstream's own release of the EXACT
  # same version — no ABI risk — and put them where the binary looks.
  # Verified: hash below matches upstream's published sha256sum.txt.
  #
  # NOTE the url is derived from ollamaBase.version, so a nixpkgs bump
  # cannot silently pair the binary with a mismatched runtime: the version
  # follows automatically and the pinned hash then fails the build until
  # it is deliberately updated. Loud failure, not quiet breakage. To
  # update: bump nixpkgs, take the new hash from the release's
  # sha256sum.txt, and re-run the acceptance check in docs/studio/phase-3.md.
  mlxRuntime = unstablePkgs.fetchurl {
    url = "https://github.com/ollama/ollama/releases/download/v${ollamaBase.version}/ollama-darwin.tgz";
    hash = "sha256-LEWGX5S84NTR0lZ2A90v2srzdVhSIKF1qkgAEFGT024=";
  };

  # The search path is derived from the binary's own location — measured,
  # with OLLAMA_DEBUG=1:
  #   <prefix>/bin/lib/ollama, <prefix>/lib/ollama, <prefix>/bin
  # NOTE: OLLAMA_LIBRARY_PATH exists as a string in the binary but 0.34.3
  # does NOT read it (absent from the server's env dump; setting it changes
  # nothing). So the libraries must sit beside the binary, which means
  # rebuilding the tree rather than setting a variable.
  #
  # COPIED, not symlinked: Go resolves its own executable path, so a
  # symlinked bin/ollama would make the search resolve back to the original
  # store path and miss these libraries entirely. This is the one
  # non-obvious constraint here — do not "tidy" it into a symlinkJoin.
  #
  # Both mlx_metal_v3 and v4 are installed. This machine selects v4
  # (verified: "MLX dynamic library loaded path=.../mlx_metal_v4/
  # libmlxc.dylib"); v3 costs ~190MB and is kept so a GPU-family probe
  # change cannot silently break a headless box. Drop it to halve the
  # closure if that is ever worth more than the safety.
  ollama =
    unstablePkgs.runCommand "ollama-${ollamaBase.version}-mlx" {
      inherit (ollamaBase) meta;
      passthru = {inherit (ollamaBase) version;};
    } ''
      mkdir -p $out
      cp -R ${ollamaBase}/. $out/
      chmod -R u+w $out
      tar -xzf ${mlxRuntime} -C $out/lib/ollama mlx_metal_v3 mlx_metal_v4
      test -f $out/lib/ollama/mlx_metal_v4/mlx.metallib
      test -f $out/bin/ollama && test ! -L $out/bin/ollama
    '';

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

  # Auto-login, and it is load-bearing rather than a convenience.
  #
  # Measured 2026-10-31 (docs/studio/phase-2.md): after an unattended
  # reboot this box came back with NO tailnet. Tailscale's macOS GUI app
  # launches at boot but cannot establish the tunnel without a login
  # session — no `utun` interface exists at all, and its CLI hangs
  # (exit 124) because the backend lives in the GUI session. Ollama then
  # cannot bind its MagicDNS name and sits in `spawn scheduled` with
  # `last exit code = 78: EX_CONFIG`, retrying forever against a
  # prerequisite that never arrives. The machine was only reachable on
  # the LAN.
  #
  # So a session has to exist from boot. This is available only because
  # FileVault is off, and the cost is an unlocked desktop — acceptable
  # here (physically secure, no Apple ID, no personal data, only
  # re-downloadable weights) and NOT acceptable on the mini, which holds
  # an iCloud session. Do not copy this there.
  #
  # INCOMPLETE ON ITS OWN: macOS also needs the obfuscated password in
  # /etc/kcpassword, which this option does not write — without it the
  # user is merely preselected at loginwindow. That step is manual
  # (System Settings > Users & Groups > "Automatically log in as"),
  # deliberately, because the declarative alternative is storing the
  # login password in sops to be written back out in a trivially
  # reversible format. Declared here anyway so the intent is in git.
  #
  # One-line disable: drop this and turn auto-login off in System
  # Settings — then accept LAN-only access after a reboot.
  system.defaults.loginwindow.autoLoginUser = username;

  # No desktop, so no wallpaper. modules/wallpaper.nix is on by default for
  # every Mac and warns on every activation here that
  # ~/Documents/Wallpapers does not exist. Harmless (it skips and the
  # rebuild succeeds), but a headless inference server has no business
  # setting one, and a warning nobody will ever act on trains you to
  # ignore activation output — which is where the Remote Login drift
  # warning below also lives.
  majordouble.wallpaper.enable = false;

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

  # Four things this box depends on are NOT expressible in nix-darwin
  # 26.05, so they are bootstrap steps recorded in docs/studio/phase-1.md
  # rather than silently omitted (the fourth, auto-login's
  # /etc/kcpassword, is covered at the autoLoginUser block below):
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

  # The CLI needs telling where the server is. `ollama` defaults to
  # 127.0.0.1:11434, and the daemon below binds the MagicDNS name instead,
  # so without this EVERY ollama command on this host fails with "could not
  # connect to ollama server" while the service is running perfectly. It is
  # the direct cost of the tailnet bind, and it is not optional.
  #
  # Same variable the daemon sets, for the opposite reason: there it is the
  # listen address, here it is the dial address. They must not drift apart.
  environment.variables.OLLAMA_HOST = "studio.jaguar-duckbill.ts.net:11434";

  # Ollama, bound to this node's MagicDNS name so it is reachable ONLY
  # from the tailnet: http://studio.jaguar-duckbill.ts.net:11434
  #
  # This deliberately does NOT use the mini's loopback + `tailscale serve`
  # pattern, and the reason is Ollama-specific. Ollama validates the HTTP
  # Host header (DNS-rebinding protection) against localhost plus whatever
  # OLLAMA_HOST names. `tailscale serve` forwards the original Host, so
  # every proxied request arrived as the tailnet name and Ollama answered
  # 403. Measured, not assumed: a `Host: 127.0.0.1` override returned 200
  # through the same proxy, and OLLAMA_ORIGINS (including `*`) does not
  # affect this check — it governs CORS only. tailscale serve has no
  # Host-rewrite option.
  #
  # Binding the MagicDNS name makes the Host match, and keeps the security
  # property that actually matters: the socket is on the tailscale
  # interface alone (verified: `LISTEN 100.126.144.70:11434`), so nothing
  # is exposed to the LAN or the internet, and WireGuard already encrypts
  # the transport. The alternative that preserves a loopback bind — a
  # Host-rewriting proxy in front — was rejected as a whole extra daemon
  # for no real gain in exposure.
  #
  # Consequence to know: this makes the service depend on tailscaled
  # having assigned the address. At boot Ollama will exit with
  # "bind: can't assign requested address" until it has; KeepAlive plus
  # ThrottleInterval retries every 15s until the bind succeeds, so it
  # self-heals rather than needing a kick. If Tailscale on macOS turns out
  # to need a GUI login, the tailnet is down after an unattended reboot
  # regardless of how Ollama is bound — that is a Tailscale question, not
  # an Ollama one, and it is on the reboot test list.
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
  # One-line disable: comment out this block and rebuild. There is no
  # serve config to retract — that is part of the point.
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
        # Tailnet interface ONLY — see the Host-header discussion above.
        # Ollama has no authentication and its API can pull, delete and run
        # models, so the bind address is the entire access control here: it
        # must stay a MagicDNS name (tailscale interface), never 0.0.0.0, a
        # LAN address, or a routable one.
        OLLAMA_HOST = "studio.jaguar-duckbill.ts.net:11434";

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
