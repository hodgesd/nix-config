# hosts/common/darwin/desktop/swiftbar-config.nix
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  home-manager.users.${config.majordouble.user} = {
    programs.swiftbar = {
      enable = true;

      # relative to $HOME; this matches your existing usage
      pluginsDir = "Library/Application Support/SwiftBar/Plugins";

      # 'inputs' is available here because your parent module (hodgesd.nix) accepts `inputs`;
      # Nix passes matching args to imported modules (same-behavior shown in the Flakes book).
      repoPath = inputs.swiftbar_plugins;

      # Source plugins from the pinned flake input on all machines (reproducible,
      # CI-verified). To iterate on plugins locally, edit them in the
      # swiftbar_plugins repo, push, then `nix flake update swiftbar_plugins`.
      repoLocalPath = null;

      repoFiles = [
        "daily_news_uv.2hr.py"
        "market_indices_uv.30m.py"
        "microcenter_deals_uv.6hr.py"
        "bball.1d.py"
      ];
    };
  };

  # Set SwiftBar preferences to point to the correct plugin directory
  system.defaults.CustomUserPreferences = {
    "com.ameba.SwiftBar" = {
      PluginDirectory = "${config.users.users.${config.majordouble.user}.home}/Library/Application Support/SwiftBar/Plugins";
      MakePluginExecutable = 1;
    };
  };
}
