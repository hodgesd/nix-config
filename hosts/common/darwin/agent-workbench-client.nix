# hosts/common/darwin/agent-workbench-client.nix
# Mac-side client for the VM agent workbench
# (hosts/nixos/nixos-infra/agent-workbench.nix): herdr only, workstation
# Macs only. Primary use: `herdr --remote workbench` (ssh alias in
# home/modules/services/ssh.nix) shows the VM desk in a local terminal.
# Secondary: a local desk driving the Homebrew opencode. Start the local
# server from a GUI terminal, not an SSH session: panes inherit the
# server's launch context and Keychain-backed tools fail otherwise (herdr
# troubleshooting docs).
#
# pi is deliberately NOT installed here. It has no permission prompts by
# design; on the VM the unprivileged `agent` user makes that acceptable,
# on a Mac it would run as the admin user with the sops age key and the
# SSH keys in reach. Use pi through `herdr --remote workbench` instead.
#
# Update: `nix flake update llm-agents` → CI → `just`. Never `herdr update`
# (read-only store; herdr's docs say package-manager installs update there).
# Disable: drop this file from hosts/common/darwin-common.nix imports; the
# next `just` removes herdr and the numtide trust together.
{
  inputs,
  lib,
  machine,
  system,
  ...
}: let
  llm = inputs.llm-agents.packages.${system};
in
  lib.mkIf (machine.primaryUse != "server") {
    environment.systemPackages = [llm.herdr];

    # Third-party binary cache. Trusting this key means accepting numtide's
    # signed build of any path we request from it — the same key the VM
    # (agent-workbench.nix) and CI (build.yaml) already trust. Without it
    # herdr (Rust+Zig) compiles from source on every bump. Lists merge with
    # base.nix; kept here, not there, so removing the module removes the
    # trust and the mini never trusts a cache it doesn't use.
    nix.settings = {
      substituters = ["https://cache.numtide.com"];
      trusted-public-keys = ["niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="];
    };
  }
