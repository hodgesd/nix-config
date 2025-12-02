# Tmux configuration module
{
  config,
  pkgs,
  lib,
  ...
}: {
  programs.tmux = {
    enable = true;
    clock24 = true;
    historyLimit = 10000;
    plugins = with pkgs.tmuxPlugins; [gruvbox];
    extraConfig = ''
      new-session -s main
      bind-key -n C-a send-prefix
    '';
  };
}
