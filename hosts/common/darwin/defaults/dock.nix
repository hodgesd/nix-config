# hosts/common/darwin/defaults/dock.nix
# Dock and Activity Monitor preferences
{...}: {
  # Dock persistent apps (pinned applications)
  # Empty list = no pinned apps, managed manually by user
  system.defaults.dock.persistent-apps = [];

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
