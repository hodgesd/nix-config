{ inputs, pkgs, unstablePkgs, ... }:

let
  inherit (inputs) nixpkgs nixpkgs-unstable;
in
{
  # Allow installation of non-free packages (e.g., vscode extensions)
  nixpkgs.config.allowUnfree = true;

  # Globally installed packages on the system
  environment.systemPackages = with pkgs; [

    # From unstable channel: tools not yet in stable
    nixpkgs-unstable.legacyPackages.${pkgs.system}.beszel     # Tool from unstable, context-specific

    ## Stable packages ##
    act               # Run GitHub Actions locally
    ansible           # Configuration management tool
    btop              # Modern resource monitor
    coreutils         # GNU core utilities (ls, cat, etc.)
    diffr             # Side-by-side diffs with syntax highlighting
    difftastic        # Structural diff tool (better diffs for code)
    drill             # DNS lookup tool, like dig
    du-dust           # Modern disk usage (du) tool with TUI
    dua               # Disk usage analyzer with interactive TUI
    duf               # Disk usage/free space utility (modern df)
    entr              # Run commands when files change (watch alternative)
    fastfetch         # Fast system info fetcher (like neofetch)
    fd                # Simple, fast and user-friendly alternative to `find`
    ffmpeg            # Multimedia framework for video/audio conversion
    figurine          # Pretty print small text banners
    fira-code         # Font with ligatures for coding
    fira-mono         # Fira Mono font (non-ligature version)
    gh                # GitHub CLI
    git-crypt         # Encrypt secrets in Git repos
    go                # Go programming language
    iperf3            # Network performance measurement
    ipmitool          # Manage IPMI-enabled devices (server management)
    jetbrains-mono    # JetBrains programming font
    just              # Command runner (like Make, but simpler)
    mosh              # Mobile shell that keeps sessions alive
    nmap              # Network scanner and mapper
    qemu              # Hardware virtualization (VMs, emulation)
    ripgrep           # Fast grep alternative
    skopeo            # Work with remote container images
    smartmontools     # Monitor HDD/SSD health using SMART
    tree              # Visualize directory trees
    unzip             # Extract ZIP archives
    watch             # Re-run a command periodically
    wget              # Command-line downloader
    zoxide            # Smarter `cd` command replacement

    # Requires `nixpkgs.config.allowUnfree = true`
  ];
}
