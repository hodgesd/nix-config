# SSH configuration module
{
  config,
  pkgs,
  lib,
  ...
}: {
  programs.ssh = {
    enable = true;
    matchBlocks = {
      # ~/.ssh/config
      "github.com" = {
        hostname = "ssh.github.com";
        port = 443;
      };
      # Skip host-key prompts only on the LAN and the tailnet, where hosts
      # get reprovisioned; everything else keeps normal strict checking.
      "192.168.1.* *.ts.net" = {
        extraOptions = {
          StrictHostKeyChecking = "no";
          UserKnownHostsFile = "/dev/null";
        };
      };
      # No global `Host *` user override: SSH uses your local username by
      # default. Add per-host blocks here for servers that need a specific user.
    };
  };
}
