{
  config,
  inputs,
  pkgs,
  name,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ./../../common/nixos-common.nix
    ./../../common/common-packages.nix
    ./beszel.nix
  ];

  ## DEPLOYMENT
  deployment = {
    targetHost = "nvllama";
    targetUser = "root";
    buildOnTarget = true;
    allowLocalDeployment = true;
    tags = ["nvllama"];
  };

  # # Secrets management configuration
  # sops = {
  #   defaultSopsFile = ./../../../secrets/secrets.yaml;
  #   defaultSopsFormat = "yaml";
  #   age = {
  #     sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  #     keyFile = "/root/.config/sops/age/keys.txt";
  #   };
  #   secrets = {
  #     morphnix-smb-user = { };
  #     morphnix-smb-pass = { };
  #   };
  # };

  # Boot configuration
  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  # Network configuration
  networking = {
    firewall.enable = false;
    hostName = "nvllama";
    interfaces.ens18 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "10.42.1.100";
          prefixLength = 21;
        }
      ];
    };
    defaultGateway = "10.42.0.254";
    nameservers = ["10.42.0.253"];
    # Add custom routing rule for local network
    localCommands = ''
      ip rule add to 10.42.0.0/21 priority 2500 lookup main || true
    '';
  };

  # System localization
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  services.beszel-agent = {
    enable = true;
    #groups = ["beszel" "video"];
    gpu = true;
  };

  services.xserver = {
    enable = false;
    videoDrivers = ["nvidia"];
  };

  # List services that you want to enable:
  services.openssh.enable = true;
  services.qemuGuest.enable = true;

  # userland
  home-manager.users.${username} = {imports = [./../../../home/default.nix];};
  users.users.${username} = {
    isNormalUser = true;
    description = username;
    extraGroups = ["networkmanager" "wheel" "docker"];
    packages = with pkgs; [
      home-manager
    ];
  };

  # System packages configuration
  environment.systemPackages = with pkgs; [
    ansible
    colmena
    htop
    inxi
    just
    ripgrep
    pciutils
    python3
    tmux
    wget
  ];

  # Hardware configuration
  hardware = {
    graphics = {
      enable = true;
      enable32Bit = true;
    };
    nvidia = {
      modesetting.enable = true;
      open = false;
      nvidiaSettings = true;
      powerManagement.enable = true;
    };
    nvidia-container-toolkit.enable = true;
  };

  # # Filesystem mounts
  # fileSystems."/mnt/jbod" = {
  #   device = "//10.42.1.10/jbod";
  #   fsType = "cifs";
  #   options = [
  #     "username=${config.sops.secrets.morphnix-smb-user.path}"
  #     "password=${config.sops.secrets.morphnix-smb-pass.path}"
  #     "x-systemd.automount"
  #     "noauto"
  #   ];
  # };
}
