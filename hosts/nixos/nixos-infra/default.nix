# nixos-infra: Proxmox guest VM on the HP mini PC.
# Runs the easy-afd app (easy-afd.nix, proxy.nix), the docker compose
# estate under /srv/homelab, nightly NAS backups (backup.nix), and the
# UNAS "Data" share mount (storage.nix). Shared server baseline
# (tailscale, docker, ssh, firewall, user) comes from
# hosts/common/nixos-common.nix.
{pkgs, ...}: {
  imports = [
    ./hardware-configuration.nix
    ./easy-afd.nix
    ./proxy.nix
    ./backup.nix
    ./storage.nix
  ];

  # Matches the release the VM was installed with. NEVER bump this —
  # it gates stateful data migrations, not features.
  system.stateVersion = "25.11";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # DHCP with a router reservation (192.168.1.216); hostname is set by
  # nix (networking.hostName), not by the DHCP server.
  networking.networkmanager.settings = {
    main.hostname-mode = "none";
  };

  # Set up for tailscale subnet-router / exit-node use.
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  # Proxmox guest agent: lets vzdump snapshot-backups freeze the fs
  # for a consistent image (enable "QEMU Guest Agent" in the VM's
  # Proxmox Options too).
  services.qemuGuest.enable = true;

  environment.systemPackages = with pkgs; [
    curl
    htop
    tmux
    jq
    dnsutils
    # The Mac SSHes in from Ghostty; without its terminfo, TERM=xterm-ghostty
    # breaks less/htop/etc.
    ghostty.terminfo
  ];
}
