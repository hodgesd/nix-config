# hosts/common/common-packages.nix
{
  pkgs,
  unstablePkgs,
  machine,
  lib,
  ...
}: {
  # Globally installed packages on the system.
  # Core set goes everywhere; heavyweight interactive/dev/media tooling is
  # darwin-only so headless NixOS servers keep a lean closure (the full set
  # roughly triples a server's system size — qemu, ffmpeg, go, act, …).
  environment.systemPackages = with pkgs;
    [
      # From unstable channel
      unstablePkgs.beszel
      unstablePkgs.uv

      # Development tools
      gh # GitHub CLI
      git # Version control
      git-lfs # Git Large File Storage
      git-crypt # Encrypt secrets in Git repos
      just # Command runner

      # System monitoring & management
      btop # Modern resource monitor
      dust # Modern disk usage (du) tool with TUI (formerly du-dust)
      dua # Disk usage analyzer with interactive TUI
      duf # Disk usage/free space utility (modern df)
      fastfetch # Fast system info fetcher
      smartmontools # Monitor HDD/SSD health using SMART

      # Network tools
      drill # DNS lookup tool, like dig
      iperf3 # Network performance measurement
      mosh # Mobile shell that keeps sessions alive
      wget # Command-line downloader

      # File & text utilities
      coreutils # GNU core utilities
      diffr # Side-by-side diffs with syntax highlighting
      difftastic # Structural diff tool
      entr # Run commands when files change
      fd # Fast alternative to `find`
      micro # Terminal text editor
      ripgrep # Fast grep alternative
      tree # Visualize directory trees
      unzip # Extract ZIP archives
      watch # Re-run a command periodically

      # Misc
      figurine # Pretty print text banners (shell banner uses it)

      # Containers
      lazydocker # Docker TUI
    ]
    ++ lib.optionals (machine.type == "darwin") [
      unstablePkgs.yt-dlp

      act # Run GitHub Actions locally
      ansible # Configuration management tool
      go # Go programming language
      ipmitool # Manage IPMI-enabled devices
      nixpkgs-fmt # Nix code formatter
      nmap # Network scanner and mapper
      ffmpeg # Video/audio conversion
      qemu # Hardware virtualization
      skopeo # Work with remote container images
    ];
}
