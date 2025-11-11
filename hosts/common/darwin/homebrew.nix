# hosts/common/darwin/homebrew.nix
# Homebrew packages and Mac App Store apps
{ ... }:
{
  homebrew = {
    enable = true;
    onActivation = {
      cleanup = "zap";
      autoUpdate = true;
      upgrade = true;
    };
    global.autoUpdate = true;

    brews = [ ];
    taps = [ ];

    casks = [
      # --- Mac Utilities ---
      "default-folder-x"
      "istat-menus"
      "omnidisksweeper"
      "rectangle"
      "TheBoredTeam/boring-notch/boring-notch"
      "karabiner-elements"

      # --- Developer & Power Tools ---
      "ghostty"
      "launchbar"
      "raycast"
      "sf-symbols"
      "syntax-highlight"
      "warp"

      # --- Communication & Productivity ---
      "chatgpt"
      "discord"
      "obsidian"
      "netnewswire"
      "popclip"
      "reminders-menubar"

      # --- Browsers ---
      "brave-browser"
      "vivaldi"

      # --- Media & Gaming ---
      "steam"
      "xnapper"

      # --- Virtualization / System Management ---
      "orbstack"
      "balenaetcher"
      "jordanbaird-ice"
    ];

    masApps = {
      "Amphetamine" = 937984704;
      "Drafts" = 1435957248;
      "Dynamo" = 1445910651;
      "Fantastical" = 975937182;
      "Goodnotes" = 1444383602;
      "Keynote" = 409183694;
      "Mona" = 1659154653;
      "Numbers" = 409203825;
      "Pages" = 409201541;
      "PDF Expert" = 1055273043;
      "RegEx Lab" = 1252988123;
    };
  };
}
