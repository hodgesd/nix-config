# hosts/common/darwin/homebrew.nix
{
  config,
  lib,
  machine,
  pkgs,
  ...
}: {
  # Set Homebrew environment variables
  environment.variables = {
    # Update Homebrew once per day instead of on every command
    HOMEBREW_AUTO_UPDATE_SECS = "86400"; # 24 hours (86400 seconds)

    # Hide Homebrew hints/tips, analytics and donation notices.
    HOMEBREW_NO_ENV_HINTS = "1";
  };

  # Pinned Homebrew (5.0.12) only knows macOS <= 26 (Tahoe); on a newer beta it
  # returns :dunno and `brew bundle` aborts. Mirror nix-darwin's bundle command
  # but, only when running macOS > 26, prepend HOMEBREW_FAKE_MACOS=26.0 (injected
  # into the command since the activation `sudo` strips the environment). No-op
  # on Tahoe and earlier. Drop once the pinned Homebrew knows the newer macOS.
  system.activationScripts.homebrew.text = lib.mkForce ''
    # nix-homebrew prepends this to `homebrew.text` with lib.mkBefore, and
    # our mkForce discards it — so it has to be re-added by hand or brew
    # itself never gets set up.
    #
    # This is not theoretical: without it, /opt/homebrew/Library/Homebrew
    # stayed symlinked to whatever brew was current the day the machine was
    # first activated (2026-02 on the mini), and every later change to the
    # pinned brew was silently ignored. It surfaced on 2026-08-09 when
    # Homebrew's cask API outgrew that stale brew and `brew bundle` began
    # crashing in api/cask.rb, failing every activation.
    ${config.system.activationScripts.setup-homebrew.text}

    # Homebrew Bundle
    echo >&2 "Homebrew bundle..."
    if [ -f "${config.homebrew.brewPrefix}/brew" ]; then
      fakeMacOS=""
      if [ "$(/usr/bin/sw_vers -productVersion | cut -d. -f1)" -gt 26 ]; then
        fakeMacOS="HOMEBREW_FAKE_MACOS=26.0"
      fi

      # brew 6 refuses to load formulae from third-party taps until the tap
      # is explicitly trusted (installing one can execute arbitrary code).
      # Trust exactly the taps this repo declares, and nothing else: the
      # check stays live for anything not in `homebrew.taps`, and the
      # acknowledgement lives in git history rather than in per-machine
      # state a rebuilt Mac would silently lose. `|| true` because older
      # brews have no `trust` subcommand.
      ${lib.concatMapStringsSep "\n" (tap: ''
        PATH="${config.homebrew.brewPrefix}:$PATH" \
        sudo --user=${lib.escapeShellArg config.homebrew.user} --set-home \
          brew trust ${lib.escapeShellArg tap.name} >/dev/null 2>&1 || true
      '')
      config.homebrew.taps}

      PATH="${config.homebrew.brewPrefix}:${lib.makeBinPath [pkgs.mas]}:$PATH" \
      sudo \
        --user=${lib.escapeShellArg config.homebrew.user} \
        --set-home \
        $fakeMacOS ${config.homebrew.onActivation.brewBundleCmd}
    else
      echo -e "\e[1;31merror: Homebrew is not installed, skipping...\e[0m" >&2
    fi
  '';

  homebrew = {
    enable = true;
    onActivation = {
      cleanup = "none"; # ← "zap" (cleanup), "none" (safe)
      # Don't auto-update on rebuild: avoids the giant "New Formulae"/"New
      # Casks" dump (and keeps rebuilds reproducible).
      autoUpdate = false;
      upgrade = true;
    };
    global = {
      autoUpdate = false;
      brewfile = true;
    };

    brews =
      [
        # Everywhere: darwin/desktop/skhd.nix writes ~/.config/skhd/skhdrc
        # and bootstraps the service on every darwin host.
        "jackielii/tap/my-skhd"
      ]
      ++ lib.optionals (machine.primaryUse != "server") [
        "opencode"
      ];
    taps = [
      "jackielii/tap"
    ];

    # Casks are an allowlist per role, not a denylist. A server gets the
    # first two groups; workstations get everything.
    #
    # This is a reliability boundary as much as a tidiness one. `brew
    # bundle` is all-or-nothing: one rotted vendor download URL fails the
    # bundle, which fails the whole activation — that is exactly how the
    # fastmail cask (pinned 1.0.7, 404ing) blocked a switch on the mini on
    # 2026-08-09. Every cask listed for the monitoring host is a third
    # party that can break its `darwin-rebuild`, so the list is short and
    # deliberate. Allowlist rather than denylist so casks added for the
    # laptops never silently land on the server.
    #
    # Nothing already installed is ever removed by narrowing this:
    # onActivation.cleanup is "none".
    casks =
      [
        # Required everywhere, server included: the uptime compose stack
        # addresses OrbStack's socket (modules/darwin/compose-stack.nix).
        "orbstack"
      ]
      ++ [
        # Also on the server. Criterion: apps this repo already writes
        # config for on every darwin host — leaving them uninstalled there
        # would mean shipping config for something that isn't present —
        # plus the basics for actually sitting at the machine.
        "karabiner-elements" # configured by darwin/desktop/karabiner.nix
        "swiftbar" # configured by darwin/desktop/swiftbar-config.nix
        "ghostty"
        "obsidian"
        "rectangle"
        "vivaldi"
      ]
      ++ lib.optionals (machine.primaryUse != "server") [
        "balenaetcher"
        "brave-browser"
        "chatgpt"
        "citrix-workspace"
        "claude"
        "codexbar"
        "cursor"
        "default-folder-x"
        "desktoppr" # Command-line wallpaper manager
        "discord"
        "fastmail"
        "istat-menus"
        "jordanbaird-ice"
        "launchbar"
        "netnewswire"
        "popclip"
        "reminders-menubar"
        "sf-symbols"
        "steam"
        "syntax-highlight"
        "TheBoredTeam/boring-notch/boring-notch"
        "unifi-identity-endpoint"
        "xnapper"
      ];

    # Skipped on the server (mini): mas-cli installs trip over Spotlight
    # indexing on that host, and a headless monitoring box has no use for
    # Keynote or Fantastical anyway. This was a hand-edit living
    # uncommitted in the mini's checkout since 2026-01; gating it on the
    # machine registry is the same fix the repo already uses for
    # laptop-only settings (see darwin/laptop-defaults.nix).
    masApps = lib.mkIf (machine.primaryUse != "server") {
      "Amphetamine" = 937984704;
      "Drafts" = 1435957248;
      "Dynamo" = 1445910651;
      "Fantastical" = 975937182;
      # "Goodnotes" = 1444383602;
      "Keynote" = 409183694;
      "Mona" = 1659154653;
      "Numbers" = 409203825;
      "Pages" = 409201541;
      "PDF Expert" = 1055273043;
      "RegEx Lab" = 1252988123;
    };
  };
}
