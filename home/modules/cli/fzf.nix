# FZF configuration
{
  config,
  pkgs,
  lib,
  ...
}: {
  programs.fzf = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    tmux.enableShellIntegration = true;
    defaultOptions = ["--no-mouse"];
  };
}
