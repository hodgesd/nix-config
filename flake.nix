# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-darwin.url = "github:NixOS/nixpkgs/nixpkgs-25.05-darwin";

#   nix-darwin.url = "github:lnl7/nix-darwin/nix-darwin-25.05";
    nix-darwin.url = "github:lnl7/nix-darwin/nix-darwin-25.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs-darwin";

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
#    nix-homebrew.url = "git+https://github.com/zhaofengli/nix-homebrew?ref=refs/pull/71/merge";
#    homebrew-core = { url = "github:homebrew/homebrew-core"; flake = false; };
#    homebrew-cask = { url = "github:homebrew/homebrew-cask"; flake = false; };
#    homebrew-bundle = { url = "github:homebrew/homebrew-bundle"; flake = false; };

    home-manager.url = "github:nix-community/home-manager/release-25.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    swiftbar_plugins = {
      url = "github:hodgesd/swiftbar_plugins";
      flake = false;   # repo has no flake.nix; treat as raw files
    };
  };

  outputs = { ... }@inputs:
    with inputs;
    let
      inherit (self) outputs;

      stateVersion = "24.05";
      libx = import ./lib { inherit inputs outputs stateVersion; };

    in {

      darwinConfigurations = {
        mbp = libx.mkDarwin { hostname = "mbp"; };
        mini = libx.mkDarwin { hostname = "mini"; };
        air = libx.mkDarwin { hostname = "air"; };
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

      };

    };

}
