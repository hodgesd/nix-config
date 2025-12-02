# hosts/common/common-packages.nix
{ pkgs, unstablePkgs, ... }:
{
  # Allow installation of non-free packages
  nixpkgs.config.allowUnfree = true;

  # Globally installed packages on the system
  environment.systemPackages = with pkgs; [
    # From unstable channel
    unstablePkgs.beszel
    unstablePkgs.uv
    unstablePkgs.yt-dlp

    # Development tools
    act               # Run GitHub Actions locally
    ansible           # Configuration management tool
    gh                # GitHub CLI
    git               # Version control
    git-lfs           # Git Large File Storage
    git-crypt         # Encrypt secrets in Git repos
    go                # Go programming language
    just              # Command runner

    # System monitoring & management
    btop              # Modern resource monitor
    du-dust           # Modern disk usage (du) tool with TUI
    dua               # Disk usage analyzer with interactive TUI
    duf               # Disk usage/free space utility (modern df)
    fastfetch         # Fast system info fetcher
    ipmitool          # Manage IPMI-enabled devices
    smartmontools     # Monitor HDD/SSD health using SMART

    # Network tools
    drill             # DNS lookup tool, like dig
    iperf3            # Network performance measurement
    mosh              # Mobile shell that keeps sessions alive
    nmap              # Network scanner and mapper
    wget              # Command-line downloader

    # File & text utilities
    comma             # Run programs without installing them
    coreutils         # GNU core utilities
    diffr             # Side-by-side diffs with syntax highlighting
    difftastic        # Structural diff tool
    entr              # Run commands when files change
    fd                # Fast alternative to `find`
    micro             # Terminal text editor
    nixpkgs-fmt       # Nix code formatter
    ripgrep           # Fast grep alternative
    tree              # Visualize directory trees
    unzip             # Extract ZIP archives
    watch             # Re-run a command periodically

    # Multimedia
    ffmpeg            # Video/audio conversion
    figurine          # Pretty print text banners

    # Virtualization & containers
    lazydocker        # Docker TUI
    qemu              # Hardware virtualization
    skopeo            # Work with remote container images
  ];
}
