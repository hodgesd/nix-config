# helpers.nix
{
  inputs,
  outputs,
  stateVersion,
  ...
}: let
  machines = import ./machines.nix;
in {
  mkDarwin = {
    hostname,
    username ? "hodgesd",
    system ? "aarch64-darwin",
  }: let
    inherit (inputs.nixpkgs) lib;
    unstablePkgs = inputs.nixpkgs-unstable.legacyPackages.${system};
    machine = machines.${hostname};
    customConfPath = ./../hosts/darwin/${hostname}/default.nix;
    hostSpecificModules =
      if builtins.pathExists customConfPath
      then [customConfPath]
      else [];
  in
    inputs.nix-darwin.lib.darwinSystem {
      specialArgs = {inherit system inputs username unstablePkgs machine;};
      modules =
        [
          # Import custom options module
          ./options.nix
          # Set majordouble config values
          {
            config.majordouble = {
              user = username;
              machine = {
                inherit (machine) hostname type formFactor primaryUse chip;
                specs = machine.specs or {};
              };
            };
          }
          ../hosts/common/common-packages.nix
          ../hosts/common/darwin-common.nix
        # Configure Nix settings
        {
          nix.settings = {
            trusted-users = ["root" username];
            experimental-features = ["nix-command" "flakes"];
          };
        }
        inputs.home-manager.darwinModules.home-manager
        {
          networking.hostName = hostname;
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "backup";
          home-manager.extraSpecialArgs = {inherit inputs;};
          home-manager.users.${username} = {
            imports = [./../home/default.nix];
          };
        }
          inputs.nix-homebrew.darwinModules.nix-homebrew
          {
            nix-homebrew = {
              enable = true;
              enableRosetta = true;
              autoMigrate = true;
              mutableTaps = true;
              user = username;
            };
          }
        ]
        ++ hostSpecificModules;
    };

  mkNixos = {
    hostname,
    username ? "hodgesd",
    system ? "x86_64-linux",
  }: let
    inherit (inputs.nixpkgs) lib;
    unstablePkgs = inputs.nixpkgs-unstable.legacyPackages.${system};
    machine = machines.${hostname};
    customConfPath = ./../hosts/nixos/${hostname}/default.nix;
    # Check if the actual file exists, not just the directory
    hostSpecificModules =
      if builtins.pathExists customConfPath
      then [customConfPath]
      else [];
  in
    inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {inherit inputs outputs stateVersion username unstablePkgs machine;};
      modules =
        [
          # Import custom options module
          ./options.nix
          # Set majordouble config values
          {
            config.majordouble = {
              user = username;
              machine = {
                inherit (machine) hostname type formFactor primaryUse chip;
                specs = machine.specs or {};
              };
            };
          }
          ../hosts/common/common-packages.nix
          ../hosts/common/nixos-common.nix
          {
            networking.hostName = hostname;
            system.stateVersion = stateVersion;

            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "backup";
            home-manager.extraSpecialArgs = {inherit inputs;};
            home-manager.users.${username} = {imports = [./../home/default.nix];};
          }
        ]
        ++ hostSpecificModules;
    };
}
