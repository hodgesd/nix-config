# hosts/common/darwin-common.nix
{ inputs, outputs, config, lib, hostname, system, username, pkgs, ... }:
let
  # Define unstablePkgs here
  unstablePkgs = import inputs.nixpkgs-unstable {
    inherit system;
    config.allowUnfree = true;
  };
in
{
  imports = [
    inputs.home-manager.darwinModules.home-manager
    ./skhd.nix
    ./karabiner.nix
  ];

  users.users.hodgesd.home = "/Users/${username}";

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
    # Darwin-only packages
    pkgs.aerospace
    pkgs.iina
    pkgs.lima
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
  };

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
      # "karabiner-elements"

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
      "whisky"
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

    #SwiftBar default plugin directory
    "com.ameba.SwiftBar" = {
      PluginDirectory = "${config.users.users.hodgesd.home}/Library/Application Support/SwiftBar/Plugins";
    };
  };

  home-manager.backupFileExtension = lib.mkForce "hm-backup";

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;

    # 👇 make flake inputs available inside your HM user config (hodgesd.nix)
    extraSpecialArgs = { inherit inputs; };

    # (A) point HM to your user config
    users.hodgesd = import ../../home/hodgesd.nix;

    # (B) optional: share modules (e.g., the SwiftBar module file)
    sharedModules = [ ../../modules/swiftbar.nix ];
  };
}
