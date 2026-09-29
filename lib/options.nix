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
        type = lib.types.enum ["laptop" "desktop" "server" "vm"];
        description = "Machine form factor";
      };

      primaryUse = lib.mkOption {
        type = lib.types.str;
        description = "Primary use case for this machine";
      };

      chip = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "CPU/chip type (null for VMs)";
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

    wallpaper = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Select the macOS wallpaper with desktoppr at home-manager activation
          (modules/wallpaper.nix), once per `path`. A directory selects that
          folder as the wallpaper source; a file sets a static picture. macOS
          14+ offers no scriptable way to turn on "Change picture", so the
          rotation toggle and its interval are a one-time step in System
          Settings → Wallpaper after the first switch.
        '';
      };

      path = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Image file or directory of images. Defaults to
          /Users/{username}/Documents/Wallpapers (iCloud-synced).
        '';
      };
    };
  };
}
