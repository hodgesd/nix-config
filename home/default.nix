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
    ./modules/core/environment.nix
    ./modules/core/shell.nix
    ./modules/core/git.nix
    ./modules/cli/tmux.nix
    ./modules/cli/fzf.nix
    ./modules/cli/eza.nix
    ./modules/cli/starship.nix
    ./modules/desktop/swiftbar.nix
    ./modules/services/ssh.nix
    ./modules/files/aerospace.nix
  ];

  programs.home-manager.enable = true;
  programs.nix-index.enable = true;

  home.packages = with pkgs; [jankyborders];
}
