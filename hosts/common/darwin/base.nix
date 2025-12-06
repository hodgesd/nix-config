# hosts/common/darwin/base.nix
# Core Nix settings and user configuration for Darwin systems
{
  config,
  ...
}: {
  users.users.${config.majordouble.user}.home = "/Users/${config.majordouble.user}";

  nix = {
    settings = {
      warn-dirty = false;
      # Build optimization
      max-jobs = "auto";
      cores = 0;
      # Better caching
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };

    channel.enable = false;

    # Automatic garbage collection
    gc = {
      automatic = true;
      interval.Day = 7;
      options = "--delete-older-than 30d";
    };

    # Automatic store optimization
    optimise.automatic = true;
  };

  system.stateVersion = 5;
  nixpkgs.config.allowUnfree = true;

  # Enable zsh system-wide (needed for login shell)
  programs.zsh = {
    enable = true;
    enableCompletion = true;
  };

  system.primaryUser = config.majordouble.user;
  security.pam.services.sudo_local.touchIdAuth = true;

  # reloads system settings without requiring a reboot
  system.activationScripts.activateSettings.text = ''
    /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
  '';
}
