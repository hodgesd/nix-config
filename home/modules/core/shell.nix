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
    autocd = true;

    shellAliases = {
      "..." = "cd ../..";
    };

    # Only show banner on login shells (not every subshell)
    loginExtra = ''
      ${pkgs.figurine}/bin/figurine -f "Doom.flf" mbp
    '';
  };

  # Environment variables
  home.sessionVariables = {
    EDITOR = "micro";
    LLM_MODEL = "m7b";
  };

  programs.bash.enable = true;
}
