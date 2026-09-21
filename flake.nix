# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    # Tier-2 (best-effort) upstream; deliberately NOT following our nixpkgs —
    # hermes pins its own tested deps. Update with: nix flake update hermes-agent
    hermes-agent.url = "github:NousResearch/hermes-agent";
    # Tier-2 like hermes-agent: herdr, OpenCode and pi for the agent workbench
    # (hosts/nixos/nixos-infra/agent-workbench.nix). Deliberately NOT following
    # our nixpkgs — numtide only builds/caches against its own pin; following
    # would rebuild herdr (Rust+Zig) on every deploy. Update with:
    #   nix flake update llm-agents
    llm-agents.url = "github:numtide/llm-agents.nix";
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
