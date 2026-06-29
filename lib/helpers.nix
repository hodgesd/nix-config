# helpers.nix
{
  inputs,
  outputs,
  ...
}: let
  machines = import ./machines.nix;
in {
  mkDarwin = {
    hostname,
    system ? "aarch64-darwin",
  }: let
    inherit (inputs.nixpkgs) lib;
    unstablePkgs = inputs.nixpkgs-unstable.legacyPackages.${system};
    # Enrich the registry entry with its hostname (derived from the attr key)
    # so `machine.hostname` is available to every module, including home-manager.
    machine = machines.${hostname} // {inherit hostname;};
    # Username comes from the machine registry, defaulting to "hodgesd".
    username = machine.username or "hodgesd";
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
                inherit hostname;
                inherit (machine) type formFactor primaryUse chip;
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
            home-manager.extraSpecialArgs = {inherit inputs machine username unstablePkgs;};
            home-manager.users.${username} = {
              imports = [./../home/default.nix];
            };
          }
          inputs.nix-homebrew.darwinModules.nix-homebrew
          ({pkgs, ...}: {
            nix-homebrew = {
              enable = true;
              enableRosetta = true;
              autoMigrate = true;
              mutableTaps = true;
              user = username;
              # Patch brew 5.0.12 to handle empty `depends_on.macos: {}` cask API
              # entries (discord, steam, rectangle, etc.). Upstream fix is in
              # 5.1.x but requires ruby_4_0, not yet in nixpkgs 25.05.
              package =
                (pkgs.applyPatches {
                  name = "brew-5.0.12-cask-api-patched-src";
                  src = inputs.nix-homebrew.inputs.brew-src;
                  patches = [./patches/brew-cask-api.patch];
                })
                // {
                  version = "5.0.12";
                };
            };
          })
        ]
        ++ hostSpecificModules;
    };
}
