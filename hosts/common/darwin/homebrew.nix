# hosts/common/darwin/homebrew.nix
{
  config,
  lib,
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
    # Homebrew Bundle
    echo >&2 "Homebrew bundle..."
    if [ -f "${config.homebrew.brewPrefix}/brew" ]; then
      fakeMacOS=""
      if [ "$(/usr/bin/sw_vers -productVersion | cut -d. -f1)" -gt 26 ]; then
        fakeMacOS="HOMEBREW_FAKE_MACOS=26.0"
      fi
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
      cleanup = "none";  # ← "zap" (cleanup), "none" (safe)
      # Don't auto-update on rebuild: avoids the giant "New Formulae"/"New
      # Casks" dump (and keeps rebuilds reproducible).
      autoUpdate = false;
      upgrade = true;
    };
    global = {
      autoUpdate = false;
      brewfile = true;
    };

    brews = [
      "opencode"
      "jackielii/tap/my-skhd"
    ];
    taps = [
      "jackielii/tap"
    ];

    casks = [
      "balenaetcher"
      "brave-browser"
      "chatgpt"
      "citrix-workspace"
      "claude"
      "cursor"
      "default-folder-x"
      "desktoppr" # Command-line wallpaper manager
      "discord"
      "fastmail"
      "ghostty"
      "istat-menus"
      "jordanbaird-ice"
      "karabiner-elements"
      "launchbar"
      "netnewswire"
      "obsidian"
      "orbstack"
      "popclip"
      "rectangle"
      "reminders-menubar"
      "sf-symbols"
      "steam"
      "swiftbar"
      "syntax-highlight"
      "TheBoredTeam/boring-notch/boring-notch"
      "vivaldi"
      "xnapper"
    ];

    masApps = {
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
