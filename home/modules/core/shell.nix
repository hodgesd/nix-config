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

    shellAliases = {
      ".." = "cd ..";
      "..." = "cd ../..";
      "...." = "cd ../../..";
      "....." = "cd ../../../..";
      "......" = "cd ../../../../..";
      "......." = "cd ../../../../../..";
      "........" = "cd ../../../../../../..";
    };

    initExtra = ''
      # Comma function for nix-index
      , () {
        nix run nixpkgs#comma -- "$@"
      }

      # ASCII art banner
      ${pkgs.figurine}/bin/figurine -f "Doom.flf" mbp
    '';
  };

  # Environment variables
  home.sessionVariables = {
    EDITOR = "micro";
    TERM = "xterm-256color";
    LLM_MODEL = "m7b";
    CLICOLOR = "1";
    LSCOLORS = "gxfxcxdxbxgggdabagacad";
  };

  # PATH additions
  home.sessionPath = [
    "/opt/homebrew/bin"
    "$HOME/go/bin"
  ];

  programs.bash.enable = true;
}
