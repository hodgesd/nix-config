# modules/swiftbar.nix
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.swiftbar;
  inherit (lib) mkEnableOption mkIf mkOption types mapAttrs';

  # Make pluginsDir absolute (if user passes an absolute path, keep it)
  pluginsDirAbs =
    if lib.hasPrefix "/" cfg.pluginsDir
    then cfg.pluginsDir
    else "${config.home.homeDirectory}/${cfg.pluginsDir}";
in {
  options.programs.swiftbar = {
    enable = mkEnableOption "SwiftBar";
    package = mkOption {
      type = types.nullOr types.package;
      default = null;
      description = "SwiftBar package (null if using Homebrew cask)";
    };
    appPath = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Path to an externally installed SwiftBar.app (e.g. the Homebrew cask); used for autostart when package is null";
    };
    autostart = mkOption {
      type = types.bool;
      default = true;
    };

    # You can still let users override this with an absolute path if they want
    pluginsDir = mkOption {
      type = types.str;
      default = "Library/Application Support/SwiftBar/Plugins";
      description = "SwiftBar plugins directory (relative to $HOME or absolute).";
    };

    repoPath = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Flake input path to the plugin repository (used as fallback)";
    };
    repoLocalPath = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Local filesystem path to the plugin repository (bypasses Nix store caching)";
    };
    repoFiles = mkOption {
      type = types.listOf types.str;
      default = [];
    };

    plugins = mkOption {
      type = types.attrsOf (types.submodule ({name, ...}: {
        options = {
          filename = mkOption {
            type = types.str;
            default = name;
          };
          text = mkOption {
            type = types.nullOr types.lines;
            default = null;
          };
          source = mkOption {
            type = types.nullOr types.path;
            default = null;
          };
          executable = mkOption {
            type = types.bool;
            default = true;
          };
        };
      }));
      default = {};
    };
  };

  config = mkIf cfg.enable (let
    useOutOfStore = cfg.repoLocalPath != null;

    # Store-backed plugins: { filename = <store path>; }
    repoPlugins = lib.optionalAttrs (!useOutOfStore && cfg.repoPath != null) (
      builtins.listToAttrs (map (fname: lib.nameValuePair fname "${cfg.repoPath}/${fname}") cfg.repoFiles)
    );
    explicitPlugins = mapAttrs' (name: plugin:
      lib.nameValuePair plugin.filename (
        if plugin.text != null
        then pkgs.writeText plugin.filename plugin.text
        else plugin.source
      ))
    cfg.plugins;
    copiedPlugins = repoPlugins // explicitPlugins;
    executableFor = fname:
      lib.findFirst (p: p.filename == fname) {executable = true;} (builtins.attrValues cfg.plugins);
  in {
    home.packages = lib.optionals (cfg.package != null) [cfg.package];

    # SwiftBar 2.x keys each plugin (enabled state and menu bar position) by its
    # symlink-resolved path. A home.file symlink resolves into a new /nix/store
    # path on every switch, so SwiftBar treats each update as remove + add and
    # forgets the menu bar order. Out-of-store symlinks resolve to the repo
    # checkout (stable); store-backed plugins are copied in as real files below.
    home.file =
      (lib.optionalAttrs (useOutOfStore && cfg.repoFiles != []) (
        builtins.listToAttrs (map
          (fname:
            lib.nameValuePair "${pluginsDirAbs}/${fname}"
            {source = config.lib.file.mkOutOfStoreSymlink "${cfg.repoLocalPath}/${fname}";})
          cfg.repoFiles)
      ))
      // {
        "${pluginsDirAbs}/.keep".text = "";
      };

    # Runs after linkGeneration so home-manager has already removed the symlinks
    # it managed in earlier generations. Files are only rewritten when their
    # contents change, so unchanged plugins aren't reloaded; plugins dropped from
    # the config are removed via the .nix-managed manifest.
    home.activation.swiftbarPlugins = lib.hm.dag.entryAfter ["linkGeneration"] ''
      dir=${lib.escapeShellArg pluginsDirAbs}
      manifest="$dir/.nix-managed"
      run mkdir -p "$dir"
      if [ -f "$manifest" ]; then
        while IFS= read -r old; do
          case " ${lib.concatStringsSep " " (builtins.attrNames copiedPlugins)} " in
            *" $old "*) ;;
            *) [ -n "$old" ] && run rm -f "$dir/$old" ;;
          esac
        done < "$manifest"
      fi
      ${lib.concatStrings (lib.mapAttrsToList (fname: src: let
          dest = "\$dir/${fname}";
          mode =
            if (executableFor fname).executable
            then "755"
            else "644";
        in ''
          if [ -L "${dest}" ] || ! cmp -s ${lib.escapeShellArg "${src}"} "${dest}"; then
            run rm -f "${dest}"
            run install -m ${mode} ${lib.escapeShellArg "${src}"} "${dest}"
          fi
        '')
        copiedPlugins)}
      if [ -z "''${DRY_RUN:-}" ]; then
        printf '%s\n' ${lib.escapeShellArgs (builtins.attrNames copiedPlugins)} > "$manifest"
      fi
    '';

    # Auto-start at login (nix-darwin)
    launchd.agents.swiftbar = mkIf (cfg.autostart && (cfg.package != null || cfg.appPath != null)) {
      enable = true;
      config = {
        ProgramArguments = [
          (
            if cfg.package != null
            then "${cfg.package}/Applications/SwiftBar.app/Contents/MacOS/SwiftBar"
            else "${cfg.appPath}/Contents/MacOS/SwiftBar"
          )
        ];
        KeepAlive = true;
        RunAtLoad = true;
      };
    };
  });
}
