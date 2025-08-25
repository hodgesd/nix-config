{ config, lib, pkgs, ... }:
let
  cfg = config.programs.swiftbar;
  inherit (lib) mkEnableOption mkIf mkOption types mapAttrs';
in
{
  options.programs.swiftbar = {
    enable    = mkEnableOption "SwiftBar";
    package   = mkOption { type = types.package; default = pkgs.swiftbar; };
    autostart = mkOption { type = types.bool; default = true; };
    pluginsDir = mkOption {
      type = types.str;
      default = "Library/Application Support/SwiftBar/Plugins";
    };

    # SIMPLE MODE: pull selected files from a repo path
    repoPath = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to your SwiftBar plugins repo (e.g. a flake input).";
    };
    repoFiles = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Exact filenames in repo root to install.";
    };

    # Optional: still allow one-off inline/sourced plugins
    plugins = mkOption {
      type = types.attrsOf (types.submodule ({ name, ... }: {
        options = {
          filename = mkOption { type = types.str; default = name; };
          text     = mkOption { type = types.nullOr types.lines; default = null; };
          source   = mkOption { type = types.nullOr types.path;  default = null; };
          executable = mkOption { type = types.bool; default = true; };
        };
      }));
      default = {};
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ cfg.package ];

    # (A) Files from your repo
    home.file = (lib.optionalAttrs (cfg.repoPath != null && cfg.repoFiles != []) (
      builtins.listToAttrs (map (fname:
        lib.nameValuePair
          "${cfg.pluginsDir}/${fname}"
          { source = cfg.repoPath + "/${fname}"; executable = true; }
      ) cfg.repoFiles)
    ))
    # (B) Plus any explicit single-file plugins
    // (mapAttrs' (name: plugin:
      let
        dest = "${cfg.pluginsDir}/${plugin.filename}";
        payload =
          if plugin.text != null then { text = plugin.text; executable = plugin.executable; }
          else                        { source = plugin.source; executable = plugin.executable; };
      in lib.nameValuePair dest payload
    ) cfg.plugins);

    # Auto-start at login (nix-darwin)
    launchd.user.agents.swiftbar = mkIf cfg.autostart {
      serviceConfig = {
        ProgramArguments = [ "${cfg.package}/Applications/SwiftBar.app/Contents/MacOS/SwiftBar" ];
        KeepAlive = true;
        RunAtLoad = true;
      };
    };
  };
}
