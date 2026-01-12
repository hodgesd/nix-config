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

      # Point to local git repo to bypass Nix store caching (hodgesd only)
      # On other users/machines, falls back to inputs.swiftbar_plugins from GitHub
      repoLocalPath =
        if config.majordouble.user == "hodgesd"
        then "/Users/hodgesd/PycharmProjects/swiftbar_plugins"
        else null;

      repoFiles = [
        "daily_news_uv.2hr.py"
        "bball.1d.py"
      ];
    };
  };
}
