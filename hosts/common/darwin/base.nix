# hosts/common/darwin/base.nix
# Core Nix settings and user configuration for Darwin systems
{
  inputs,
  config,
  system,
  ...
}: {
  imports = [];

  users.users.${config.majordouble.user}.home = "/Users/${config.majordouble.user}";

  nix = {
    settings = {
      experimental-features = ["nix-command" "flakes"];
      warn-dirty = false;
    };
    channel.enable = false;
  };

  nix.enable = true;
  system.stateVersion = 5;

  nixpkgs.config.allowUnfree = true;

  # Nix registry shortcuts
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
  };

  system.primaryUser = config.majordouble.user;
  security.pam.services.sudo_local.touchIdAuth = true;

  system.activationScripts.activateSettings.text = ''
    /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
  '';
}
