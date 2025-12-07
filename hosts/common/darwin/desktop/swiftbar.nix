# hosts/common/darwin/swiftbar.nix
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

      repoFiles = [
        "daily_news_uv.2hr.py"
        "bball.1d.py"
      ];
      # Cache buster: 2025-12-06-18:05
    };
  };
}
