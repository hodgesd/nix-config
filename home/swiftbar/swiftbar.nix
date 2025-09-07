# home/swiftbar/swiftbar.nix
{ pkgs, lib, inputs, ... }:
{
  programs.swiftbar = {
    enable = true;

    # relative to $HOME; this matches your existing usage
    pluginsDir = "Library/Application Support/SwiftBar/Plugins";

    # 'inputs' is available here because your parent module (hodgesd.nix) accepts `inputs`;
    # Nix passes matching args to imported modules (same-behavior shown in the Flakes book).
    repoPath  = inputs.swiftbar_plugins;

    repoFiles = [
      "daily_news_uv.2hr.py"
    ];
  };
}
