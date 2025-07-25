{ inputs, outputs, config, lib, hostname, system, username, pkgs, unstablePkgs, ... }:
let
  inherit (inputs) nixpkgs nixpkgs-unstable;
in
{
  users.users.hodgesd.home = "/Users/hodgesd";

  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      warn-dirty = false;
    };
    channel.enable = false;
  };
#  services.nix-daemon.enable = true;
  nix.enable = true;
  system.stateVersion = 5;

  nixpkgs = {
    config.allowUnfree = true;
    hostPlatform = lib.mkDefault "${system}";
  };

  environment.systemPackages = with pkgs; [
    ## unstable
    unstablePkgs.colmena
    unstablePkgs.ollama
    unstablePkgs.yt-dlp
#    unstablePkgs.rustdesk

    ## stable CLI
    pkgs.comma
    pkgs.iina
    pkgs.just
    pkgs.lima
    pkgs.nix
#    pkgs.tailscale
#    pkgs.llm        # too complex, erases downloaded plugins and models.
#    pkgs.rustdesk   #

#    pkgs.net-news-wire
  ];

  fonts.packages = [
  pkgs.nerd-fonts.fira-code
  pkgs.nerd-fonts.fira-mono
  pkgs.nerd-fonts.hack
  pkgs.nerd-fonts.jetbrains-mono
  ];

  # pins to stable as unstable updates very often
  nix.registry = {
    n.to = {
      type = "path";
      path = inputs.nixpkgs;
    };
    u.to = {
      type = "path";
      path = inputs.nixpkgs-unstable;
    };
  };

  programs.nix-index.enable = true;

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    promptInit = builtins.readFile ./../../data/mac-dot-zshrc;
  };

  homebrew = {
    enable = true;
    onActivation = {
      cleanup = "zap";                
      autoUpdate = true;
      upgrade = true;
    };
    global.autoUpdate = true;
    brews = [
    ];
    taps = [
    ];
    casks = [
#     "nikitabobko/tap/aerospace"
      "alcove"
      "bentobox"                           # A window manager
      "default-folder-x"
      "discord"                            # Chat and community app
      "istat-menus"                        # Menu bar system monitor
      "jordanbaird-ice"                   # Organize/hide menu bar icons
      "launchbar"
      "netnewswire"
      "obsidian"                           # Markdown-based knowledge base
      "omnidisksweeper"                    # Find large files and free space
      "orbstack"
      "popclip"
      "raycast"
      "rectangle"
      "sf-symbols"
      "steam"
      "swiftbar"
      "syntax-highlight"
#      "tailscale"
      "vivaldi"
      "warp"
      "xnapper"
      # "clop"                            # (not installed) Clipboard manager
      # "lm-studio"                          # Run local AI models
      # "macwhisper"                         # Local Whisper transcription
      # "marta"                              # Dual-pane file manager
      # "shortcat"                           # Keyboard-driven UI navigation
#      "ollama"                             # Run local LLMs

    ];
    masApps = {
      "Affinity Photo" = 824183456;
      "Affinity Publisher" = 881418622;
      "Amphetamine" = 937984704;           # Prevent Mac from sleeping
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

#      "Strategery" = 298908505;            # mas doesnt yet work with ios apps.
    #  "UTM" = 1538878817;                  # Virtual machines on Mac
    #  "rCmd" = 1596283165;                 # Remote Mac launcher
#      "Snippety" = 1530751461;             # Text expansion/snippet manager
    };
  };

  system.primaryUser = "hodgesd";
#  security.pam.enableSudoTouchIdAuth = true;
   security.pam.services.sudo_local.touchIdAuth = true;
  # macOS configuration

  system.activationScripts.activateSettings.text = ''
  # Apply user settings without logout/login cycle
  /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
  '';
  system.defaults = {
    NSGlobalDomain.AppleShowAllExtensions = true;                     # Show all file extensions — helpful for clarity.
    NSGlobalDomain.AppleShowScrollBars = "Always";                   # Always-visible scrollbars — good for visibility.
    NSGlobalDomain.NSUseAnimatedFocusRing = false;                   # Disables animated focus ring — minor visual polish.
    NSGlobalDomain.NSNavPanelExpandedStateForSaveMode = true;        # Always expand save dialogs — very useful.
    NSGlobalDomain.NSNavPanelExpandedStateForSaveMode2 = true;       # Same as above, modern version — good.
    NSGlobalDomain.PMPrintingExpandedStateForPrint = true;           # Always expand print dialogs — saves clicks.
    NSGlobalDomain.PMPrintingExpandedStateForPrint2 = true;          # Same as above, modern version — good.
    NSGlobalDomain.ApplePressAndHoldEnabled = false;                 # Enables key repeat instead of accent menu — preferred by coders.
    NSGlobalDomain.InitialKeyRepeat = 25;                            # Short delay before key repeat starts — snappy typing.
    NSGlobalDomain.KeyRepeat = 2;
    NSGlobalDomain."com.apple.mouse.tapBehavior" = 1;
    NSGlobalDomain.NSWindowShouldDragOnGesture = true;               # Allows dragging windows with a three-finger gesture — useful.
    NSGlobalDomain.NSAutomaticSpellingCorrectionEnabled = false;
    LaunchServices.LSQuarantine = false;                             # Skip "Are you sure you want to open?" — power-user move.
    loginwindow.GuestEnabled = false;                                # Disable guest account — good for security.
    finder.FXPreferredViewStyle = "Nlsv";                            # Use list view in Finder — widely preferred.
  };

  system.defaults.CustomUserPreferences = {
      "com.apple.finder" = {
        ShowExternalHardDrivesOnDesktop = true;
        ShowHardDrivesOnDesktop = false;
        ShowMountedServersOnDesktop = false;
        ShowRemovableMediaOnDesktop = true;
        _FXSortFoldersFirst = true;
        # When performing a search, search the current folder by default
        FXDefaultSearchScope = "SCcf";
        DisableAllAnimations = true;
        NewWindowTarget = "PfDe";
        NewWindowTargetPath = "file://$\{HOME\}/Desktop/";
        AppleShowAllExtensions = true;
        FXEnableExtensionChangeWarning = false;
        ShowStatusBar = true;
        ShowPathbar = true;
        WarnOnEmptyTrash = false;
      };
      "com.apple.desktopservices" = {
        # Avoid creating .DS_Store files on network or USB volumes
        DSDontWriteNetworkStores = true;
        DSDontWriteUSBStores = true;
      };
      "com.apple.dock" = {
        autohide = false;
        launchanim = false;
        static-only = false;
        show-recents = false;
        show-process-indicators = true;
        orientation = "left";
        tilesize = 36;
        minimize-to-application = true;
        mineffect = "scale";
        enable-window-tool = false;
      };
      "com.apple.ActivityMonitor" = {
        OpenMainWindow = true;
        IconType = 5;
        SortColumn = "CPUUsage";
        SortDirection = 0;
      };

#      "com.apple.Safari" = {
#        # Privacy: don’t send search queries to Apple
#        UniversalSearchEnabled = false;
#        SuppressSearchSuggestions = true;
#      };
      # Safari preferences removed to fix permissions error
      # These need to be configured manually through Safari preferences
      # or using a different approach that supports containerized apps
      "com.apple.AdLib" = {
        allowApplePersonalizedAdvertising = false;
      };
      "com.apple.SoftwareUpdate" = {
        AutomaticCheckEnabled = true;
        ScheduleFrequency = 1;
        AutomaticDownload = 1;
        CriticalUpdateInstall = 1;
      };
      "com.apple.TimeMachine".DoNotOfferNewDisksForBackup = true;
      # Prevent Photos from opening automatically when devices are plugged in
      "com.apple.ImageCapture".disableHotPlug = true;
      # Turn on app auto-update
      "com.apple.commerce".AutoUpdate = true;

  };

}
