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
      # "uninstall" removes anything installed that this allowlist doesn't
      # declare (apps' prefs/support files are kept — that would be "zap").
      # Anything worth keeping must be listed below or it disappears on the
      # next activation of that host.
      cleanup = "uninstall"; # ← "zap" | "uninstall" (cleanup), "none" (safe)
      # Don't auto-update on rebuild: avoids the giant "New Formulae"/"New
      # Casks" dump (and keeps rebuilds reproducible).
      autoUpdate = false;
      # Rebuilds only converge to this config (install missing, cleanup
      # undeclared) — they never upgrade what's installed. That keeps
      # `just` fast and deterministic, avoids one bad cask download failing
      # the whole activation, and can't upgrade OrbStack out from under the
      # mini's containers mid-switch. Upgrade deliberately instead:
      # `brew upgrade && mas upgrade`.
      upgrade = false;
    };
    global = {
      autoUpdate = false;
      brewfile = true;
    };

    brews = [
      # darwin/desktop/skhd.nix writes ~/.config/skhd/skhdrc and bootstraps
      # the service on every darwin host.
      "jackielii/tap/my-skhd"
      "mas" # keep brew's mas current; nix's pkgs.mas is only the PATH fallback
      "opencode"
      # 2026-08-30 formulae curation (mini converge): everything else on the
      # old installed set was either nix-duplicated (git, gh, btop, go, nmap,
      # wget, iperf3, fastfetch, … — see common-packages.nix) or runtime
      # cruft nix manages better (php, node, nvm, python@). These two are
      # macOS-specific and not in nixpkgs' closure here:
      "mactop" # Apple-Silicon per-core/GPU top
      "screenresolution"
      # Phase 4 apple bridge: fast EventKit reads (events + reminders).
      # Deliberately brew, not nix (not in nixpkgs) — and the TCC grant
      # keys on this stable binary, surviving nix env rebuilds.
      "ical-buddy"
    ];
    taps = [
      "jackielii/tap"
      # Kept from the 2026-08-30 mini cleanup (deliberately NOT untapped):
      "hpedrorodrigues/tools"
      "nikitabobko/tap"
      # Deliberately allowed to untap: mongodb/brew, theboredteam/* (with
      # its boring-notch cask), and the deprecated homebrew/bundle,
      # homebrew/services, github/gh — those three are absorbed into brew
      # core and re-declaring them can error on modern brews.
    ];

    # One cask list for every darwin host. The per-role allowlist was
    # collapsed on 2026-08-19: the mini deliberately installs the full
    # workstation set for now, pending a decision on which apps are
    # mbp-only. Two standing cautions from the allowlist era still apply:
    # `brew bundle` is all-or-nothing, so one rotted vendor download URL
    # fails the whole activation (the pinned fastmail 1.0.7 404ing blocked
    # a mini switch on 2026-08-09), and onActivation.cleanup is
    # "uninstall", so removing an entry (or leaving an installed app
    # undeclared) removes the app on that host's next activation.
    casks = [
      # The uptime compose stack addresses OrbStack's socket
      # (modules/darwin/compose-stack.nix).
      "orbstack"
      "karabiner-elements" # configured by darwin/desktop/karabiner.nix
      "swiftbar" # configured by darwin/desktop/swiftbar-config.nix
      "balenaetcher"
      "brave-browser"
      "chatgpt"
      "citrix-workspace"
      "claude"
      "codexbar"
      "crossover"
      "cursor"
      "default-folder-x"
      "desktoppr" # Command-line wallpaper manager
      "discord"
      # 2026-08-30 mini-converge keepers: previously installed, now declared
      # so cleanup keeps them. Deliberately dropped in the same pass (will
      # uninstall wherever present): boring-notch, iterm2, utm, warp,
      # grammarly-desktop, zoom, raycast.
      # 2026-09-02: two of those keepers dropped again after they broke the
      # mbp switch. docker-desktop: its cask links
      # /usr/local/bin/docker-credential-osxkeychain, which OrbStack (the
      # declared runtime, see modules/darwin/compose-stack.nix) already owns
      # on every host, so the install can never succeed. dockutil: no longer
      # a cask upstream (formula only) and nothing here uses it. Both get
      # uninstalled from the mini by cleanup on its next activation.
      "fastmail"
      "ghostty"
      "git-credential-manager"
      "google-chrome"
      "google-gemini"
      "istat-menus"
      "launchbar"
      "libreoffice"
      "licecap"
      "lm-studio"
      "macwhisper"
      "microsoft-auto-update"
      "microsoft-teams"
      "netnewswire"
      "obsidian"
      "opencode-desktop"
      "popclip"
      "rectangle"
      "reminders-menubar"
      "remoteviewer"
      "sf-symbols"
      "steam"
      "syntax-highlight"
      "telegram" # native macOS client — desktop surface for the Hermes bot
      "thaw" # menu bar manager, maintained fork of the abandoned jordanbaird-ice
      "unifi-identity-endpoint"
      "vivaldi"
      "whatcable"
      "xnapper"
    ];

    # Skipped on the server (mini): mas-cli installs trip over Spotlight
    # indexing on that host, and a headless monitoring box has no use for
    # Keynote or Fantastical anyway. This was a hand-edit living
    # uncommitted in the mini's checkout since 2026-01; gating it on the
    # machine registry is the same fix the repo already uses for
    # laptop-only settings (see darwin/laptop-defaults.nix).
    masApps = lib.mkIf (machine.primaryUse != "server") {
      "1Blocker" = 1365531024;
      "Actions" = 1586435171;
      "Affinity Photo" = 824183456;
      "Affinity Publisher" = 881418622;
      "Airport Madness 3D Volume 2" = 1321684059;
      "Amphetamine" = 937984704;
      "BloonsTD6+" = 1584423325;
      "Calca" = 635758264;
      "Drafts" = 1435957248;
      "Dynamo" = 1445910651;
      "Fantastical" = 975937182;
      "Goodnotes" = 1444383602;
      "iMovie" = 408981434;
      "iThoughtsX" = 720669838;
      # Keynote/Numbers/Pages use Apple's newer unified store IDs (the
      # current 15.x versions); the old 409183694/409203825/409201541
      # receipts are stale 14.5 copies that cleanup is expected to remove.
      "Keynote" = 361285480;
      "Marked 2" = 890031187;
      "MindNode" = 6446116532;
      "Mini Metro+" = 1550663539;
      "Mona" = 1659154653;
      "Numbers" = 361304891;
      "Obsidian Web Clipper" = 6720708363;
      "Okta Verify" = 490179405;
      "OmniFocus" = 1346203938;
      "Pages" = 361309726;
      "PDF Expert" = 1055273043;
      "RegEx Lab" = 1252988123;
      "TestFlight" = 899247664;
      "The Lost City" = 1538650027;
      "Unforgetful" = 6785630295;
      "Xcode" = 497799835;
    };
  };
}
