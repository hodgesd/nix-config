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
