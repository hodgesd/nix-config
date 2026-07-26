# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nix-darwin.url = "github:lnl7/nix-darwin/nix-darwin-25.11";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    swiftbar_plugins = {
      url = "github:hodgesd/swiftbar_plugins";
      flake = false; # repo has no flake.nix; treat as raw files
    };
  };

  outputs = {self, ...} @ inputs:
    with inputs; let
      inherit (self) outputs;

      libx = import ./lib {inherit inputs outputs;};
    in {
      darwinConfigurations = {
        mbp = libx.mkDarwin {hostname = "mbp";};
        mini = libx.mkDarwin {hostname = "mini";};
        air = libx.mkDarwin {hostname = "air";};
      };

      nixosConfigurations = {
        nixos-infra = libx.mkNixos {hostname = "nixos-infra";};
      };

      formatter = {
        aarch64-darwin = nixpkgs.legacyPackages.aarch64-darwin.alejandra;
        x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.alejandra;
      };
    };
}
