{ inputs, outputs, config, lib, hostname, system, username, pkgs, unstablePkgs, ... }:
let
  inherit (inputs) nixpkgs nixpkgs-unstable;
in
{
  users.users.alex.home = "/Users/alex";

  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      warn-dirty = false;
    };
    channel.enable = false;
  };
  services.nix-daemon.enable = true;
  system.stateVersion = 5;

  nixpkgs = {
    config.allowUnfree = true;
    hostPlatform = lib.mkDefault "${system}";
  };

  environment.systemPackages = with pkgs; [
    ## unstable
    unstablePkgs.yt-dlp
    unstablePkgs.get_iplayer
    unstablePkgs.colmena

    ## stable CLI
    pkgs.comma
    pkgs.just
    pkgs.lima
    pkgs.nix
  ];

  fonts.packages = [
    (pkgs.nerdfonts.override {
      fonts = [
        "FiraCode"
        "FiraMono"
        "Hack"
        "JetBrainsMono"
      ];
    })
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
      cleanup = "none";                 # set to "zap" once brew list is set
      autoUpdate = true;
      upgrade = true;
    };
    global.autoUpdate = true;

    brews = [
  # "bitwarden-cli"                      # CLI for Bitwarden password manager
  # "borders"                          # (not installed) Window border styling tool
    ];

    taps = [
      # "FelixKratz/formulae"             # (not tapped) Source for sketchybar, a macOS status bar customizer
    ];

    casks = [
    #  "cleanshot"                          # Screenshot and annotation tool
      # "nikitabobko/tap/aerospace"       # (not installed) Tiling window manager
    #  "alacritty"                          # Fast GPU terminal emulator
    #  "alcove"                             # Minimal window manager
      # "balenaetcher"                    # (not installed) Flash OS images to USB
      # "bentobox"                           # A window manager
      # "clop"                            # (not installed) Clipboard manager
      "discord"                            # Chat and community app
      # "docker"                          # (not installed) Container management
    #  "element"                            # Decentralized Matrix messaging client
      "elgato-stream-deck"                # Macro pad management
      "flameshot"                          # Screenshot tool with annotation
      "font-fira-code"                    # Monospaced font with ligatures
      "font-fira-code-nerd-font"          # Fira Code with dev icons
      "font-fira-mono-for-powerline"      # Fira Mono font for shell prompts
      "font-hack-nerd-font"               # Hack font with icons
      "font-jetbrains-mono-nerd-font"     # JetBrains Mono with Nerd icons
      "font-meslo-lg-nerd-font"           # Meslo LG for terminal themes
    #  "ghostty"                            # Modern GPU-accelerated terminal
      # "google-chrome"                     # Google web browser
      # "iina"                               # Sleek macOS video player
      "istat-menus"                        # Menu bar system monitor
      "iterm2"                             # Advanced terminal emulator
      "jordanbaird-ice"                   # Organize/hide menu bar icons
      # "lm-studio"                          # Run local AI models
      # "macwhisper"                         # Local Whisper transcription
      # "marta"                              # Dual-pane file manager
      # "music-decoy"                        # Stops Apple Music auto-launch
      # "nextcloud"                          # Sync with self-hosted cloud
      "obsidian"                           # Markdown-based knowledge base
      "ollama"                             # Run local LLMs
    #  "omnidisksweeper"                    # Find large files and free space
      "orbstack"                           # Dev-friendly Docker + VMs
      # "openttd"                            # Open-source transport sim game
      "popclip"                            # Inline text actions
      "raycast"                            # Spotlight with power tools
      # "signal"                             # Encrypted messaging app
      # "shortcat"                           # Keyboard-driven UI navigation
      "steam"                              # Game platform
      "tailscale"                          # Peer-to-peer VPN
      "vlc"                                # Media player for any format

    ];

    masApps = {
    #  "Amphetamine" = 937984704;           # Prevent Mac from sleeping
    #  "Bitwarden" = 1352778147;            # GUI password manager
    #  "Disk Speed Test" = 425264550;       # Measure disk performance
      "Fantastical" = 975937182;           # Smart calendar and task manager
    #  "Home Assistant Companion" = 1099568401; # Smart home control app
    #  "Perplexity" = 6714467650;           # AI-powered search assistant
      "Resize Master" = 102530679;         # Batch resize and export images
    #  "rCmd" = 1596283165;                 # Remote Mac launcher
    #  "Snippety" = 1530751461;             # Text expansion/snippet manager
      # "Tailscale" = 1475387142;          # (duplicate) VPN with WireGuard
    #  "Telegram" = 747648890;              # Fast, encrypted messenger
    #  "UTM" = 1538878817;                  # Virtual machines on Mac

      # Apple productivity apps
      "Keynote" = 409183694;               # Presentations
      "Numbers" = 409203825;               # Spreadsheets
      "Pages" = 409201541;                 # Word processing
    };
  };

  # Keyboard
#  system.keyboard.enableKeyMapping = true;
  system.keyboard.remapCapsLockToEscape = false;

  # Add ability to used TouchID for sudo authentication
  security.pam.enableSudoTouchIdAuth = true;

  # macOS configuration
  system.activationScripts.postUserActivation.text = ''
    # Following line should allow us to avoid a logout/login cycle
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
    NSGlobalDomain.KeyRepeat = 2;                                    # Fast key repeat rate — nice for navigation/editing.
    NSGlobalDomain."com.apple.mouse.tapBehavior" = 1;                # Enable tap-to-click — standard for trackpads.
    NSGlobalDomain.NSWindowShouldDragOnGesture = true;               # Allows dragging windows with a three-finger gesture — useful.
    NSGlobalDomain.NSAutomaticSpellingCorrectionEnabled = false;     # No auto-correct — avoids coding headaches.
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
      "com.apple.Safari" = {
        # Privacy: don’t send search queries to Apple
        UniversalSearchEnabled = false;
        SuppressSearchSuggestions = true;
      };
      "com.apple.AdLib" = {
        allowApplePersonalizedAdvertising = false;
      };
      "com.apple.SoftwareUpdate" = {
        AutomaticCheckEnabled = true;
        # Check for software updates daily, not just once per week
        ScheduleFrequency = 1;
        # Download newly available updates in background
        AutomaticDownload = 1;
        # Install System data files & security updates
        CriticalUpdateInstall = 1;
      };
      "com.apple.TimeMachine".DoNotOfferNewDisksForBackup = true;
      # Prevent Photos from opening automatically when devices are plugged in
      "com.apple.ImageCapture".disableHotPlug = true;
      # Turn on app auto-update
      "com.apple.commerce".AutoUpdate = true;
#      "com.googlecode.iterm2".PromptOnQuit = false;
#      "com.google.Chrome" = {
#        AppleEnableSwipeNavigateWithScrolls = true;
#        DisablePrintPreview = true;
#        PMPrintingExpandedStateForPrint2 = true;
#      };
  };

}
