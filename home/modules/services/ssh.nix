# SSH configuration module
{
  config,
  pkgs,
  lib,
  ...
}: {
  programs.ssh = {
    enable = true;
    # HM 25.11 deprecates the implicit `Host *` defaults; opt out and carry
    # them over explicitly in the "*" block below.
    enableDefaultConfig = false;
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
      #
      # The old implicit HM defaults, kept verbatim. Ordered after the
      # specific blocks: ssh takes the first value it finds, so `Host *`
      # must stay last or its UserKnownHostsFile would shadow the LAN one.
      "*" = lib.hm.dag.entryAfter ["github.com" "192.168.1.* *.ts.net"] {
        forwardAgent = false;
        addKeysToAgent = "no";
        compression = false;
        serverAliveInterval = 0;
        serverAliveCountMax = 3;
        hashKnownHosts = false;
        userKnownHostsFile = "~/.ssh/known_hosts";
        controlMaster = "no";
        controlPath = "~/.ssh/master-%r@%n:%p";
        controlPersist = "no";
      };
    };
  };
}
