# hosts/common/darwin/desktop/jankyborders.nix
# JankyBorders window border configuration
{
  config,
  pkgs,
  lib,
  ...
}: {
  # Auto-start JankyBorders at login via launchd
  home-manager.users.${config.majordouble.user} = {
    launchd.agents.jankyborders = {
      enable = true;
      config = {
        ProgramArguments = [
          "/run/current-system/sw/bin/borders"
          "active_color=0xff00ff00"
          "inactive_color=0xff444444"
          "width=8.0"
        ];
        KeepAlive = true;
        RunAtLoad = true;
      };
    };
  };
}

