# hosts/common/darwin/base.nix
# Core Nix settings and user configuration for Darwin systems
{
  config,
  ...
}: {
  users.users.${config.majordouble.user}.home = "/Users/${config.majordouble.user}";

  nix = {
    settings.warn-dirty = false;
    channel.enable = false;
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

  system.activationScripts.activateSettings.text = ''
    /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
  '';
}
