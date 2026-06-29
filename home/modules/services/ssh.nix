# SSH configuration module
{
  config,
  pkgs,
  lib,
  ...
}: {
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
      # No global `Host *` user override: SSH uses your local username by
      # default. Add per-host blocks here for servers that need a specific user.
    };
  };
}
