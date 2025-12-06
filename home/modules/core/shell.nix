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
    initContent = ''
      ${builtins.readFile ../../../data/mac-dot-zshrc}

      # Initialize zoxide
      eval "$(${pkgs.zoxide}/bin/zoxide init zsh --cmd cd)"
    '';
  };

  programs.bash.enable = true;
}
