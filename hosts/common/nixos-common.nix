# hosts/common/nixos-common.nix
# Shared baseline for all NixOS hosts (servers/VMs). Darwin equivalent:
# darwin-common.nix. Home-manager is wired by mkNixos (opt-in per host),
# not imported here.
{
  pkgs,
  unstablePkgs,
  inputs,
  username,
  ...
}: {
  # Inert until a host declares majordouble.composeStacks.*
  imports = [../../modules/nixos/compose-stack.nix];

  time.timeZone = "America/Chicago";
  i18n.defaultLocale = "en_US.UTF-8";

  users.users.${username} = {
    isNormalUser = true;
    description = username;
    extraGroups = ["wheel" "docker" "networkmanager"];
    shell = pkgs.zsh;
    # Key-based LAN/console access that does NOT depend on tailscaled being
    # up — tailscale --ssh is the day-to-day path, this is the DR path.
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID3x58CGULnbDBsoQW7nOPVWMAND98rDi7IYCty5bDGX hodgesd@mbp"
    ];
  };

  programs.zsh.enable = true;

  # No Home Manager on servers, so nothing ships a ~/.zshrc; without one,
  # zsh runs its first-login zsh-newuser-install wizard. An empty file
  # suppresses it ("f" never clobbers an existing file).
  systemd.tmpfiles.rules = [
    "f /home/${username}/.zshrc 0644 ${username} users -"
  ];

  nix = {
    settings = {
      experimental-features = ["nix-command" "flakes"];
      warn-dirty = false;
      trusted-users = ["root" username];
      # CI (build.yaml) pushes nixos closures here; rebuilds on the host
      # become mostly downloads.
      substituters = ["https://hodgesd-nix-config.cachix.org"];
      trusted-public-keys = ["hodgesd-nix-config.cachix.org-1:VRtYFrJXm6UAQOXZ1xLbMfGohWyLeXKFrNb8mCc2VmM="];
    };
    channel.enable = false;

    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };
  };

  nixpkgs.config.allowUnfree = true;

  # Nix registry (matching Darwin)
  nix.registry = {
    n.to = {
      type = "path";
      path = inputs.nixpkgs;
    };
    u.to = {
      type = "path";
      path = inputs.nixpkgs-unstable;
    };
  };

  programs.nix-index.enable = true;

  virtualisation.docker = {
    enable = true;
    # 25.11's default docker (28.5.2) is marked insecure in nixpkgs;
    # move forward rather than whitelist it. Switching restarts dockerd,
    # which briefly bounces the containers.
    package = pkgs.docker_29;
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  networking.networkmanager.enable = true;

  # Tailscale from unstable, locked via flake.lock (unlike the old
  # unpinned fetchTarball). Locked rev ships 1.98.8 — the exact version
  # the VM was running at cutover, so no up/downgrade surprises. When
  # bumping nixpkgs-unstable, check the tailscale release notes; 1.98.0
  # and 1.98.1 had a Linux MagicDNS regression (NixOS/nixpkgs#520715).
  services.tailscale = {
    enable = true;
    package = unstablePkgs.tailscale;
    extraUpFlags = ["--ssh"];
  };

  # Tailnet-only by design: nothing listens on the LAN except SSH.
  networking.firewall = {
    enable = true;
    trustedInterfaces = ["tailscale0"];
  };
}
