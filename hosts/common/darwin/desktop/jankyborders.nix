# hosts/common/darwin/desktop/jankyborders.nix
# JankyBorders window border configuration
{
  config,
  pkgs,
  lib,
  ...
}: {
  # Auto-start JankyBorders at login via launchd
  launchd.agents.jankyborders = {
    enable = true;
    config = {
      ProgramArguments = [
        "/etc/profiles/per-user/${config.majordouble.user}/bin/borders"
        "active_color=0xff00ff00"
        "inactive_color=0xff444444"
        "width=8.0"
      ];
      KeepAlive = true;
      RunAtLoad = true;
    };
  };
}

