# hosts/common/darwin/homebrew.nix
{...}: {
  homebrew = {
    enable = true;
    onActivation = {
      cleanup = "zap";
      autoUpdate = true;
      upgrade = true;
    };
    global = {
      autoUpdate = true;
      brewfile = true;
    };

    brews = [
      "opencode"
      {
        name = "jackielii/tap/skhd-zig";
        start_service = true;
      }
    ];
    taps = [
      "jackielii/tap"
    ];

    casks = [
      "balenaetcher"
      "brave-browser"
      "chatgpt"
      "cursor"
      "default-folder-x"
      "desktoppr" # Command-line wallpaper manager
      "discord"
      "ghostty"
      "istat-menus"
      "jordanbaird-ice"
      "karabiner-elements"
      "launchbar"
      "netnewswire"
      "obsidian"
      "orbstack"
      "popclip"
      "raycast"
      "rectangle"
      "reminders-menubar"
      "sf-symbols"
      "steam"
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
