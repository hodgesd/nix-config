# t3-code: Proxmox guest VM on the HP mini PC (VMID 101, 4 vCPU, 12 GiB
# ballooning to 8, 64 GiB). A dedicated, disposable box for T3 Code's
# remote server, kept apart from nixos-infra so coding agents with shell
# access never share a machine with the homelab estate. Shared server
# baseline (tailscale, docker, ssh, firewall, hodgesd) comes from
# hosts/common/nixos-common.nix.
#
# Shape: T3 Code runs as its own self-managed systemd user service
# (`t3code.service`, installed by `t3 service install` under the `agent`
# user's ~/.config/systemd/user) on 127.0.0.1:3773, published over
# Tailscale Serve (HTTPS :443 on this node's MagicDNS name). The Mac pairs
# via Settings → Connections → Add environment. Nothing listens on the LAN
# except SSH. Nix deliberately does NOT define a server unit: a second
# `npx t3 serve` unit fights t3code.service for ~/.t3/userdata
# (ServerAlreadyRunningError) and breaks in-app updates, which swap the
# runtime under ~/.t3/runtime/versions and rewrite t3code.service.
#
# Security model (same as nixos-infra's agent-workbench.nix): the boundary
# is the OS user. `agent` has no wheel and no docker, so a prompt-injected
# repo cannot reach sudo or the docker socket. It IS the tailscale operator
# (needed for `tailscale serve`), so it can change what this node serves —
# acceptable because the node hosts nothing else.
#
# One-time setup after install (state, not config):
#   sudo tailscale up --ssh --operator=agent
#   ssh agent@t3-code            # then: claude (login), gh auth login
#   npx --yes t3 service install
#   tailscale serve --bg http://127.0.0.1:3773
#
# OpenCode, for T3 Code's OpenCode provider (added 2026-11-08). Same
# shape as codex on this host: the agent user's nix profile, not
# systemPackages, because nothing here can switch the system and the
# host's own rule is that per-user agent state stays state. Pinned to
# the SAME llm-agents rev flake.lock pins, so it matches nixos-infra's
# agent-workbench.nix without an unpinned ref. The next two commands read
# flake.lock and opencode.json straight from origin/main, so they do not
# care what branch or how stale the working tree is -- this host's
# checkout (~/nix-config, which T3 Code needs as its project checkout
# anyway) is routinely parked on a feature branch. gh is already
# authenticated by the step above:
#   [ -d ~/nix-config ] || gh repo clone hodgesd/nix-config ~/nix-config; cd ~/nix-config && git fetch -q origin
#   nix profile add "github:numtide/llm-agents.nix/$(git show origin/main:flake.lock | jq -r '.nodes."llm-agents".locked.rev')#opencode" --accept-flake-config
#   git show origin/main:hosts/nixos/t3-code/opencode.json | install -Dm644 /dev/stdin ~/.config/opencode/opencode.json
#   T3 Code app: Settings → Providers → OpenCode → enable
#     (= ~/.t3/userdata/settings.json  providerInstances.opencode =
#     {"driver": "opencode", "enabled": true}. `driver` is REQUIRED: an
#     entry without it fails schema validation and the server silently
#     falls back to defaults for the WHOLE file -- check the server log
#     for "failed to parse settings.json" if a toggle seems to do nothing.)
# opencode.json points OpenCode at the Mac Studio's Ollama over the
# tailnet (MagicDNS name on purpose: Ollama 403s any other Host header).
# The Studio was retired from this repo in #121 while the hardware stays
# up pending a keep/return decision; if it goes back, delete that JSON
# and `nix profile remove opencode` here. T3 Code 0.1.x calls OpenCode
# 1.14–1.x "graceful" (2.0.18+ "supported", not yet on npm stable);
# verified 1.18.33 end to end against the Studio on 2026-11-08.
# Mint a pairing link with `~/.t3/runtime/versions/<ver>/t3 pair --tailscale`.
# Update with the app's update button or `t3 update --yes`.
#
# No sops secrets here, so no .sops.yaml recipient is needed for this host.
{pkgs, ...}: {
  imports = [./hardware-configuration.nix];

  # Matches the release the VM was installed with. NEVER bump this.
  system.stateVersion = "26.05";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.networkmanager.settings.main.hostname-mode = "none";

  services.qemuGuest.enable = true;

  # 12 GiB can balloon down to 8; compressed RAM swap absorbs build spikes
  # without a swap partition.
  zramSwap.enable = true;

  # Agents and npx fetch prebuilt, dynamically linked binaries that expect
  # a conventional loader path; nix-ld provides it.
  programs.nix-ld.enable = true;

  users.users.agent = {
    isNormalUser = true;
    description = "T3 Code agent";
    shell = pkgs.zsh;
    # Start t3code.service at boot and keep it running after logout.
    linger = true;
  };

  systemd.tmpfiles.rules = [
    "f /home/agent/.zshrc 0644 agent users -"
    "d /home/agent/src 0755 agent users -"
  ];

  environment.systemPackages = with pkgs; [
    nodejs_22
    claude-code
    curl
    jq
    tmux
    htop
    ghostty.terminfo
  ];
}
