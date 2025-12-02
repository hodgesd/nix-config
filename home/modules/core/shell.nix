# Shell configuration (Zsh)
{
  config,
  pkgs,
  lib,
  ...
}: {
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    initExtra = builtins.readFile ../../data/mac-dot-zshrc;
  };

  programs.bash.enable = true;
}
