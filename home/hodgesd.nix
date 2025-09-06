# hodgesd.nix
{ config, inputs, pkgs, lib, unstablePkgs, ... }:
{
  home.stateVersion = "24.05";
  # Add these lines for SSL certificate configuration
  home.sessionVariables = {
    NIX_SSL_CERT_FILE = "/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt";
  };

  # list of programs
  # https://mipmip.github.io/home-manager-option-search


  programs.gpg.enable = true;

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.eza = {
    enable = true;
    enableZshIntegration = true;
    icons = "auto";
    git = true;
    extraOptions = [
      "--group-directories-first"
      "--header"
      "--color=auto"
    ];
  };

  programs.fzf = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    tmux.enableShellIntegration = true;
    defaultOptions = [
      "--no-mouse"
    ];
  };

  programs.git = {
    enable = true;
    userEmail = "hodgesd@gmail.com";
    userName = "Derrick Hodges";
    diff-so-fancy.enable = true;
    lfs.enable = true;
    extraConfig = {
      init = {
        defaultBranch = "main";
      };
      merge = {
        conflictStyle = "diff3";
        tool = "meld";
      };
      pull = {
        rebase = true;
      };
      # ADD THIS SECTION for SSL certificate configuration
      http = {
        sslCAinfo = "/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt";
      };
    };
  };

  programs.lf.enable = true;

  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;
    settings = pkgs.lib.importTOML ./starship/starship.toml;
  };


  programs.swiftbar = {
  enable = true;
  # optional: override; relative is fine now
  pluginsDir = "Library/Application Support/SwiftBar/Plugins";

  repoPath  = inputs.swiftbar_plugins;
  repoFiles = [
    "daily_news_uv.2hr.py"
    ];
  };

  programs.bash.enable = true;

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
  
    initExtra = ''
      ${builtins.readFile ../data/mac-dot-zshrc}
    '';
  };
  
  programs.tmux = {
    enable = true;
    #keyMode = "vi";
    clock24 = true;
    historyLimit = 10000;
    plugins = with pkgs.tmuxPlugins; [
      gruvbox
    ];
    extraConfig = ''
      new-session -s main
      bind-key -n C-a send-prefix
    '';
  };

  programs.home-manager.enable = true;
  programs.nix-index.enable = true;

  programs.bat.enable = true;
  programs.bat.config.theme = "Nord";
  #programs.zsh.shellAliases.cat = "${pkgs.bat}/bin/bat";

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;  # or `enableBashIntegration`, `enableFishIntegration`
    options = lib.mkForce [ "--cmd" "cd" ];  # use 'cd' instead of 'z'
  };

  programs.ssh = {
    enable = true;
    extraConfig = ''
      StrictHostKeyChecking no
    '';
    matchBlocks = {
      # ~/.ssh/config
      "github.com" = {
        hostname = "ssh.github.com";
        port = 443;
      };
      "*" = {
        user = "root";
      };
    };
  };

  # home/hodgesd.nix
  home.packages = with pkgs; [ jankyborders ];
  
    # Write AeroSpace config (replaces defaults)
  home.file.".aerospace.toml".source = ./aerospace/aerospace.toml;
  }
