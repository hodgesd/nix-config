# lib/options.nix
# Custom options for majordouble's nix configuration
{lib, ...}: {
  options.majordouble = {
    user = lib.mkOption {
      type = lib.types.str;
      default = "hodgesd";
      description = "Primary user name";
    };

    machine = {
      hostname = lib.mkOption {
        type = lib.types.str;
        description = "Machine hostname";
      };

      type = lib.mkOption {
        type = lib.types.enum ["darwin" "nixos"];
        description = "System type (darwin or nixos)";
      };

      formFactor = lib.mkOption {
        type = lib.types.enum ["laptop" "desktop" "server"];
        description = "Machine form factor";
      };

      primaryUse = lib.mkOption {
        type = lib.types.str;
        description = "Primary use case for this machine";
      };

      chip = lib.mkOption {
        type = lib.types.str;
        description = "CPU/chip type";
      };

      specs = {
        ram = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "RAM amount";
        };

        storage = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Storage size";
        };

        cpu = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = null;
          description = "CPU cores";
        };

        gpu = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = null;
          description = "GPU cores";
        };
      };
    };
  };
}
