# Shell configuration (Zsh)
{
  config,
  pkgs,
  lib,
  machine,
  ...
}: {
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    autocd = true;

    # Treat `#` as a comment at the prompt, as scripts already do. Without it,
    # a pasted `cmd  # note` hands the note to cmd as arguments, and any
    # backticks in the note run as a command.
    setOptions = ["INTERACTIVE_COMMENTS"];

    shellAliases = {
      "..." = "cd ../..";
    };

    # Only show banner on login shells (not every subshell)
    loginExtra = ''
      ${pkgs.figurine}/bin/figurine -f "Doom.flf" ${machine.hostname}
    '';
  };

  # Environment variables
  home.sessionVariables = {
    EDITOR = "micro";
    LLM_MODEL = "m7b";
  };

  programs.bash.enable = true;
}
