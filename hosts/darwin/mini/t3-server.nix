# T3 Code server on the mini, for Mac-native agent work: darwin builds and
# `[macos]` recipes/tests that the t3-code VM (x86_64-linux) cannot run.
# Everything else (gvii_afd, FOM) stays on t3-code. The mbp app pairs this
# as a second environment (Settings → Connections → Add environment).
#
# Security model, same as the VM's: the boundary is the OS user. `t3agent`
# is not an admin, has no password (no GUI login, no sudo), and has its own
# primary group. WHY not `staff`: home directories here are
# `drwxr-x--- <user> staff`, so a staff member can read derrickhodges'
# home — iCloud vault, sops-decrypted tokens, ~/.ssh. A prompt-injected
# repo should reach nothing but /Users/t3agent.
#
# Why a system daemon and not `t3 service install`: on macOS that installs a
# LaunchAgent in the gui/<uid> domain, which only runs while the user is
# logged in at the console. Nobody logs t3agent in, so it would never run.
# The daemon instead runs T3's own `__service-launcher`, the same
# long-lived supervisor its systemd unit runs on the VM; the launcher picks
# the active runtime version and restarts the server across in-app
# updates, so updates keep working. FileVault still gates boot (see
# default.nix): after a reboot, this starts once the box is unlocked.
#
# One-time setup after the first switch (state, not config; done 2026-11-26):
#   # Remote Login here is limited to admins (com.apple.access_ssh nests
#   # admin); t3agent needs to be added for the VM to reach it.
#   sudo dseditgroup -o edit -a t3agent -t user com.apple.access_ssh
#   # Install the runtime. It ends with "Background setup failed while
#   # starting the service (exit code 125)": that is its gui/ step, expected.
#   # Remove the LaunchAgent it wrote so a login could never start a second
#   # server against the same ~/.t3 (ServerAlreadyRunningError).
#   ssh t3agent@mini 'npx --yes t3 service install; rm -f ~/Library/LaunchAgents/com.t3tools.t3code.service.plist'
#   sudo launchctl kickstart -k system/org.nixos.t3-server
#   sudo tailscale serve --bg --https=8324 http://127.0.0.1:3773
#   ssh t3agent@mini 'claude'            # log in; then `gh auth login`
# `t3 service status` reports "not installed": it only knows its own
# LaunchAgent. Pair with `ssh t3agent@mini '~/.t3/runtime/versions/<ver>/t3
# pair --ttl 30m'` and swap its 127.0.0.1:3773 for
# mini.jaguar-duckbill.ts.net:8324 (--tailscale would try to run serve as
# t3agent, which is not the tailscale operator).
#
# Logs: /Users/t3agent/t3-server.log (the launcher) and
# ~/.t3/userdata/logs/ (the server).
# Disable: drop this file from default.nix's imports, then
# `tailscale serve --https=8324 off`. The user and its home stay (nix-darwin
# does not delete users); remove with `sudo sysadminctl -deleteUser t3agent`.
{
  pkgs,
  unstablePkgs,
  ...
}: let
  user = "t3agent";
  id = 510; # uid and gid; 501/502 are the human accounts
  home = "/Users/${user}";
  t3Home = "${home}/.t3";
in {
  users.knownUsers = [user];
  users.knownGroups = [user];

  users.groups.${user} = {
    gid = id;
    members = [user];
  };

  users.users.${user} = {
    uid = id;
    gid = id;
    inherit home;
    createHome = true;
    shell = "/bin/zsh";
    description = "T3 Code agent";
    isHidden = true; # off the login window
    # The t3-code VM's key: lets VM agents run darwin builds here as this
    # unprivileged user. Login also needs the com.apple.access_ssh step above.
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICqtGYhL9lNLBifxD6zjgV89isCQacI54IKFIgj8dxTA agent@t3-code"
    ];
    # What agents and the one-time install need. claude-code matches the VM
    # (store-pinned; update with the flake, not claude's own updater).
    # codex is T3's Codex provider (Sol). unstablePkgs, not llm-agents: same
    # version the VM runs, but from cache.nixos.org, since this host does not
    # trust numtide's cache and would otherwise build it from source.
    packages = with pkgs; [nodejs_22 claude-code unstablePkgs.codex git gh jq just];
  };

  launchd.daemons.t3-server.serviceConfig = {
    UserName = user;
    GroupName = user;
    # /bin/sh and /bin/wait4path, not the store: launchd can start a daemon
    # before /nix is mounted and then abandons it for good (see
    # whisper-stt.nix). The launcher itself lives in ~/.t3, outside the
    # store; plutil reads which version is active. Before the one-time
    # install there is no state file, so this exits and launchd retries.
    ProgramArguments = [
      "/bin/sh"
      "-c"
      ''
        /bin/wait4path /nix/store &&
        v=$(/usr/bin/plutil -extract activeVersion raw -o - ${t3Home}/runtime/service-state.json) &&
        exec ${t3Home}/runtime/versions/"$v"/t3 __service-launcher
      ''
    ];
    EnvironmentVariables = {
      HOME = home;
      USER = user;
      T3CODE_HOME = t3Home;
      PATH = "/etc/profiles/per-user/${user}/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin:/usr/sbin:/sbin";
    };
    WorkingDirectory = home;
    RunAtLoad = true;
    KeepAlive = true;
    ThrottleInterval = 30;
    ExitTimeOut = 90; # T3's own plist value; lets the server drain on stop
    # In $HOME, not ~/.t3/userdata/logs: that dir does not exist until the
    # one-time install, and launchd will not create it.
    StandardOutPath = "${home}/t3-server.log";
    StandardErrorPath = "${home}/t3-server.log";
  };
}
