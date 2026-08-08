# nixos-infra: Proxmox guest VM on the HP mini PC.
# Runs the easy-afd app (easy-afd.nix, proxy.nix), the docker compose
# estate under /srv/homelab, nightly NAS backups (backup.nix), and the
# UNAS "Data" share mount (storage.nix). Shared server baseline
# (tailscale, docker, ssh, firewall, user) comes from
# hosts/common/nixos-common.nix.
{
  config,
  pkgs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ./easy-afd.nix
    ./proxy.nix
    ./backup.nix
    ./storage.nix
    ./homelab-stack.nix
    ./hermes.nix
    ./kuma-watchdog.nix
  ];

  # Secrets: decrypted at activation by sops-nix into /run/secrets (tmpfs)
  # using this host's ssh_host_ed25519_key as the age identity. If
  # decryption fails, activation aborts BEFORE services restart — the
  # running generation is never harmed. Edit on the Mac with:
  #   sops secrets/nixos-infra.yaml
  sops = {
    defaultSopsFile = ../../../secrets/nixos-infra.yaml;
    age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
    secrets = {
      # OPENAIP/Autorouter/FAA-NMS/Kuma credentials (gunicorn env).
      # restartUnits because systemd restarts a service when its *unit*
      # changes, not when the contents of its EnvironmentFile change —
      # so rotating a credential here leaves the running process holding
      # the old value indefinitely, with the correct one already on
      # disk. Not theoretical: it is exactly how the FAA NMS credentials
      # kept returning 401 after an otherwise successful deploy.
      #
      # Only the long-running unit needs it. easy-afd-refresh and
      # easy-afd-healthcheck are timer-driven oneshots that re-exec on
      # every run, so they pick up new values already.
      easy-afd-env.restartUnits = ["easy-afd.service"];
      cloudflare-acme-env = {}; # DNS-01 token for afd.hdgs.me cert
      nas-backup-credentials = {}; # SMB creds for both UNAS shares
      homelab-env = {}; # TS_AUTHKEY for the compose tailscale sidecars
      # Decrypted pre-user-creation; makes DR rebuilds come up with the
      # same login password (mutableUsers is on, so this only seeds new
      # installs — the live shadow entry already matches).
      hodgesd-password.neededForUsers = true;
    };
  };

  users.users.hodgesd.hashedPasswordFile = config.sops.secrets.hodgesd-password.path;

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
