# hosts/common/darwin/defaults/dock.nix
# Dock and Activity Monitor preferences
{ ... }:
{
  system.defaults.CustomUserPreferences = {
    "com.apple.dock" = {
      autohide = true;
      autohide-delay = 0.0;
      autohide-time-modifier = 0.2;
      launchanim = false;
      static-only = false;
      show-recents = false;
      show-process-indicators = true;
      orientation = "left";
      tilesize = 36;
      minimize-to-application = true;
      mineffect = "scale";
      enable-window-tool = false;
    };
    "com.apple.ActivityMonitor" = {
      OpenMainWindow = true;
      IconType = 5;
      SortColumn = "CPUUsage";
      SortDirection = 0;
    };
  };
}
