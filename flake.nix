# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-darwin.url = "github:NixOS/nixpkgs/nixpkgs-25.05-darwin";
    nix-darwin.url = "github:lnl7/nix-darwin/nix-darwin-25.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs-darwin";
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    home-manager.url = "github:nix-community/home-manager/release-25.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    swiftbar_plugins = {
      url = "github:hodgesd/swiftbar_plugins";
      flake = false; # repo has no flake.nix; treat as raw files
    };
  };

  outputs = {self, ...} @ inputs:
    with inputs; let
      inherit (self) outputs;

      stateVersion = "25.05";
      libx = import ./lib {inherit inputs outputs stateVersion;};
    in {
      darwinConfigurations = {
        mbp = libx.mkDarwin {hostname = "mbp";};
        mini = libx.mkDarwin {hostname = "mini";};
        air = libx.mkDarwin {hostname = "air";};
      };

      nixosConfigurations = {
        desktop = libx.mkNixos {hostname = "desktop";};
        ktz-cloud = libx.mkNixos {hostname = "ktz-cloud";};
        morphnix = libx.mkNixos {hostname = "morphnix";};
        nix-dev = libx.mkNixos {hostname = "nix-dev";};
        nvllama = libx.mkNixos {hostname = "nvllama";};

        nixos-air = libx.mkNixos {hostname = "nixos-air";};
      };

      formatter = {
        aarch64-darwin = nixpkgs.legacyPackages.aarch64-darwin.alejandra;
        x86_64-darwin = nixpkgs.legacyPackages.x86_64-darwin.alejandra;
        x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.alejandra;
      };
    };
}
