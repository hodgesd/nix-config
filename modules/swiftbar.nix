# modules/swiftbar.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.programs.swiftbar;
  inherit (lib) mkEnableOption mkIf mkOption types mapAttrs';

  # Make pluginsDir absolute (if user passes an absolute path, keep it)
  pluginsDirAbs =
    if lib.hasPrefix "/" cfg.pluginsDir
    then cfg.pluginsDir
    else "${config.home.homeDirectory}/${cfg.pluginsDir}";
in
{
  options.programs.swiftbar = {
    enable = mkEnableOption "SwiftBar";
    package = mkOption { type = types.package; default = pkgs.swiftbar; };
    autostart = mkOption { type = types.bool; default = true; };

    # You can still let users override this with an absolute path if they want
    pluginsDir = mkOption {
      type = types.str;
      default = "Library/Application Support/SwiftBar/Plugins";
      description = "SwiftBar plugins directory (relative to $HOME or absolute).";
    };

    repoPath = mkOption { type = types.nullOr types.path; default = null; };
    repoFiles = mkOption { type = types.listOf types.str; default = [ ]; };

    plugins = mkOption {
      type = types.attrsOf (types.submodule ({ name, ... }: {
        options = {
          filename = mkOption { type = types.str; default = name; };
          text = mkOption { type = types.nullOr types.lines; default = null; };
          source = mkOption { type = types.nullOr types.path; default = null; };
          executable = mkOption { type = types.bool; default = true; };
        };
      }));
      default = { };
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ cfg.package ];



    home.file =
      # (A) Files from your repo
      (lib.optionalAttrs (cfg.repoPath != null && cfg.repoFiles != [ ]) (
        builtins.listToAttrs (map
          (fname:
            lib.nameValuePair
              "${pluginsDirAbs}/${fname}"
              { source = cfg.repoPath + "/${fname}"; executable = true; }
          )
          cfg.repoFiles)
      ))
      # (B) Plus any explicit single-file plugins
      // (mapAttrs'
        (name: plugin:
          let
            dest = "${pluginsDirAbs}/${plugin.filename}";
            payload =
              if plugin.text != null then { text = plugin.text; executable = plugin.executable; }
              else { source = plugin.source; executable = plugin.executable; };
          in
          lib.nameValuePair dest payload
        )
        cfg.plugins)
      # Ensure the directory exists (drop a .keep file)
      // {
        "${pluginsDirAbs}/.keep".text = "";
      };

    # Auto-start at login (nix-darwin)
    launchd.agents.swiftbar = mkIf cfg.autostart {
      enable = true;
      config = {
        ProgramArguments = [
          "${cfg.package}/Applications/SwiftBar.app/Contents/MacOS/SwiftBar"
        ];
        KeepAlive = true;
        RunAtLoad = true;
      };
    };
  };
}
