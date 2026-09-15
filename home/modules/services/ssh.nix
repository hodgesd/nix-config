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
    # HM 26.05 deprecated `matchBlocks` for these RFC 42-style settings:
    # keys are literal ssh_config(5) directive names.
    settings = {
      # ~/.ssh/config
      "github.com" = {
        HostName = "ssh.github.com";
        Port = 443;
      };
      # Skip host-key prompts only on the LAN and the tailnet, where hosts
      # get reprovisioned; everything else keeps normal strict checking.
      "192.168.1.* *.ts.net" = {
        StrictHostKeyChecking = "no";
        UserKnownHostsFile = "/dev/null";
      };
      # No global `Host *` user override: SSH uses your local username by
      # default. Add per-host blocks here for servers that need a specific user.
      #
      # The old implicit HM defaults, kept verbatim. Ordered after the
      # specific blocks: ssh takes the first value it finds, so `Host *`
      # must stay last or its UserKnownHostsFile would shadow the LAN one.
      "*" = lib.hm.dag.entryAfter ["github.com" "192.168.1.* *.ts.net"] {
        ForwardAgent = "no";
        AddKeysToAgent = "no";
        Compression = "no";
        ServerAliveInterval = 0;
        ServerAliveCountMax = 3;
        HashKnownHosts = "no";
        UserKnownHostsFile = "~/.ssh/known_hosts";
        ControlMaster = "no";
        ControlPath = "~/.ssh/master-%r@%n:%p";
        ControlPersist = "no";
      };
    };
  };
}
