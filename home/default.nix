# Home Manager entry point for hodgesd
{
  config,
  pkgs,
  lib,
  inputs,
  unstablePkgs,
  ...
}: {
  home.stateVersion = "24.05";

  imports = [
    # Cross-platform modules
    ./modules/core/environment.nix
    ./modules/core/shell.nix
    ./modules/core/git.nix
    ./modules/cli/tmux.nix
    ./modules/cli/fzf.nix
    ./modules/cli/eza.nix
    ./modules/cli/starship.nix
    ./modules/cli/zoxide.nix
    ./modules/services/ssh.nix
    # Note: darwin-specific modules (swiftbar, aerospace) are in hosts/common/darwin/
  ];

  programs.home-manager.enable = true;
  programs.nix-index.enable = true;

  # Note: darwin-specific packages (jankyborders) are in hosts/common/darwin/packages.nix
}
