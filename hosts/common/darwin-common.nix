# hosts/common/darwin-common.nix
{ inputs, outputs, config, lib, hostname, system, username, pkgs, unstablePkgs, ... }:
let
  inherit (inputs) nixpkgs nixpkgs-unstable;
in
{
  imports = [
    inputs.home-manager.darwinModules.home-manager
  ];

  users.users.hodgesd.home = "/Users/hodgesd";

  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      warn-dirty = false;
    };
    channel.enable = false;
  };
  nix.enable = true;
  system.stateVersion = 5;

  nixpkgs = {
    config.allowUnfree = true;
    hostPlatform = lib.mkDefault "${system}";
  };

  environment.systemPackages = with pkgs; [
    unstablePkgs.colmena
    unstablePkgs.ollama
    unstablePkgs.yt-dlp

    pkgs.aerospace
    pkgs.comma
    pkgs.iina
    pkgs.just
    pkgs.lima
    pkgs.nix
    pkgs.micro
    pkgs.lazydocker
    pkgs.brave
  ];

  fonts.packages = [
    pkgs.nerd-fonts.fira-code
    pkgs.nerd-fonts.fira-mono
    pkgs.nerd-fonts.hack
    pkgs.nerd-fonts.jetbrains-mono
  ];

  nix.registry = {
    n.to = { type = "path"; path = inputs.nixpkgs; };
    u.to = { type = "path"; path = inputs.nixpkgs-unstable; };
  };

  programs.nix-index.enable = true;

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    promptInit = builtins.readFile ./../../data/mac-dot-zshrc;
  };

  services.skhd.enable = true;

  homebrew = {
    enable = true;
    onActivation = {
      cleanup = "zap";
      autoUpdate = true;
      upgrade = true;
    };
    global.autoUpdate = true;
    brews = [ ];
    taps  = [ ];
    casks = [
      "alcove"
      "bentobox"
      "default-folder-x"
      "discord"
      "istat-menus"
      "jordanbaird-ice"
      "launchbar"
      "netnewswire"
      "obsidian"
      "omnidisksweeper"
      "orbstack"
      "popclip"
      "raycast"
      "rectangle"
      "sf-symbols"
      "steam"
      "swiftbar"
      "syntax-highlight"
      "vivaldi"
      "warp"
      "xnapper"
      # "karabiner-elements"
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

  system.primaryUser = "hodgesd";
  security.pam.services.sudo_local.touchIdAuth = true;

  system.activationScripts.activateSettings.text = ''
    /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
  '';

  system.defaults = {
    NSGlobalDomain.AppleShowAllExtensions = true;
    NSGlobalDomain.AppleShowScrollBars = "Always";
    NSGlobalDomain.NSUseAnimatedFocusRing = false;
    NSGlobalDomain.NSNavPanelExpandedStateForSaveMode = true;
    NSGlobalDomain.NSNavPanelExpandedStateForSaveMode2 = true;
    NSGlobalDomain.PMPrintingExpandedStateForPrint = true;
    NSGlobalDomain.PMPrintingExpandedStateForPrint2 = true;
    NSGlobalDomain.ApplePressAndHoldEnabled = false;
    NSGlobalDomain.InitialKeyRepeat = 25;
    NSGlobalDomain.KeyRepeat = 2;
    NSGlobalDomain."com.apple.mouse.tapBehavior" = 1;
    NSGlobalDomain.NSWindowShouldDragOnGesture = true;
    NSGlobalDomain.NSAutomaticSpellingCorrectionEnabled = false;
    LaunchServices.LSQuarantine = false;
    loginwindow.GuestEnabled = false;
    finder.FXPreferredViewStyle = "Nlsv";
  };

  system.defaults.CustomUserPreferences = {
    "com.apple.finder" = {
      ShowExternalHardDrivesOnDesktop = true;
      ShowHardDrivesOnDesktop = false;
      ShowMountedServersOnDesktop = false;
      ShowRemovableMediaOnDesktop = true;
      _FXSortFoldersFirst = true;
      FXDefaultSearchScope = "SCcf";
      DisableAllAnimations = true;
      NewWindowTarget = "PfDe";
      NewWindowTargetPath = "file://${config.users.users.hodgesd.home}/Desktop/";
      AppleShowAllExtensions = true;
      FXEnableExtensionChangeWarning = false;
      ShowStatusBar = true;
      ShowPathbar = true;
      WarnOnEmptyTrash = false;
    };
    "com.apple.desktopservices" = {
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
    "com.apple.AdLib".allowApplePersonalizedAdvertising = false;
    "com.apple.SoftwareUpdate" = {
      AutomaticCheckEnabled = true;
      ScheduleFrequency = 1;
      AutomaticDownload = 1;
      CriticalUpdateInstall = 1;
    };
    "com.apple.TimeMachine".DoNotOfferNewDisksForBackup = true;
    "com.apple.ImageCapture".disableHotPlug = true;
    "com.apple.commerce".AutoUpdate = true;
  };

  home-manager.backupFileExtension = lib.mkForce "hm-backup";
  
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;

    users.hodgesd = { pkgs, ... }: {
      home.stateVersion = "24.05";

      home.file.".skhdrc".text = ''
        hyper - s : open -a "Safari"
        hyper - d : open -a "Drafts"
        hyper - c : open -a "ChatGPT"
        hyper - t : open -a "Warp"
        hyper - p : open -a "PyCharm"
        hyper - f : open -a "Finder"
      '';

      xdg.configFile."karabiner/karabiner.json" = {
        text = ''
        {
          "global": { "check_for_updates_on_startup": true },
          "profiles": [
            {
              "name": "Default",
              "selected": true,
              "complex_modifications": {
                "rules": [
                  {
                                  "description": "Caps Lock: tap = toggle, hold = hyper",
                                  "manipulators": [
                                      {
                                          "from": { "key_code": "caps_lock" },
                                          "to": [{ 
                                              "key_code": "left_shift",
                                              "modifiers": ["left_control", "left_option", "left_command"] 
                                          }],
                                          "to_if_alone": [{ 
                                              "key_code": "caps_lock",
                                              "hold_down_milliseconds": 200
                                          }],
                                          "type": "basic"
                                      }
                                  ]
                              }
                ]
              }
            }
          ]
        }
        '';
        force = true;
      };
    };
  };
}
