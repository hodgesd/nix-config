# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-darwin.url = "github:NixOS/nixpkgs/nixpkgs-24.11-darwin";

    nix-darwin.url = "github:lnl7/nix-darwin/nix-darwin-24.11";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs-darwin";

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
#    nix-homebrew.url = "git+https://github.com/zhaofengli/nix-homebrew?ref=refs/pull/71/merge";
#    homebrew-core = { url = "github:homebrew/homebrew-core"; flake = false; };
#    homebrew-cask = { url = "github:homebrew/homebrew-cask"; flake = false; };
#    homebrew-bundle = { url = "github:homebrew/homebrew-bundle"; flake = false; };

    home-manager.url = "github:nix-community/home-manager/release-24.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";


    # --- CHANGE THESE LINES ---
    # Remove the old flake = false lines:
    # homebrew-core = { url = "github:homebrew/homebrew-core"; flake = false; };
    # homebrew-cask = { url = "github:homebrew/homebrew-cask"; flake = false; };
    # homebrew-bundle = { url = "github:homebrew/homebrew-bundle"; flake = false; }; # <-- Definitely remove this one

#    # Add these using fetchFromGitHub:
#    homebrew-core = inputs.pkgs.fetchFromGitHub {
#      owner = "Homebrew";
#      repo = "homebrew-core";
#      # Find a recent commit hash on the main/master branch of github.com/Homebrew/homebrew-core
#      # Example: (check github for a newer one)
#      rev = "e026a07c956214778c616774f062ff848a524613";
#      # Leave hash empty or wrong first, build will fail telling you the correct hash
#      hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; # Will be filled in after first build attempt
#    };
#    homebrew-cask = inputs.pkgs.fetchFromGitHub {
#      owner = "Homebrew";
#      repo = "homebrew-cask";
#      # Find a recent commit hash on the main/master branch of github.com/Homebrew/homebrew-cask
#      # Example: (check github for a newer one)
#      rev = "9361300069c58577df1a0a857e5c1b9a0c15b2ea";
#      # Leave hash empty or wrong first, build will fail telling you the correct hash
#      hash = "sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB="; # Will be filled in after first build attempt
#    };
#    # --- END OF CHANGES ---

  };

  outputs = { ... }@inputs:
    with inputs;
    let
      inherit (self) outputs;

      stateVersion = "24.05";
      libx = import ./lib { inherit inputs outputs stateVersion; };

    in {

      darwinConfigurations = {
        # personal
        mbp = libx.mkDarwin { hostname = "mbp"; };

#        slartibartfast = libx.mkDarwin { hostname = "slartibartfast"; };
#        nauvis = libx.mkDarwin { hostname = "nauvis"; };
#        mac-studio = libx.mkDarwin { hostname = "mac-studio"; };
#        mac-mini = libx.mkDarwin { hostname = "mac-mini"; };
#        mooncake = libx.mkDarwin { hostname = "mooncake"; };
#
#        # work
#        baldrick = libx.mkDarwin { hostname = "baldrick"; };
#        magrathea = libx.mkDarwin { hostname = "magrathea"; };
      };

      colmena = {
        meta = {
          nixpkgs = import inputs.nixpkgs { system = "x86_64-linux"; };
          specialArgs = {
            inherit inputs outputs stateVersion self;
          };
        };

        defaults = { lib, config, name, ... }: {
          imports = [
            inputs.home-manager.nixosModules.home-manager
          ];
        };

        # wd
        morphnix = import ./hosts/nixos/morphnix;
        nvllama = import ./hosts/nixos/nvllama;

        # test system
        # yeager = nixosSystem "x86_64-linux" "yeager" "alex";
      };

    };

}
