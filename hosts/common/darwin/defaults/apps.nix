# hosts/common/darwin/defaults/apps.nix
# Application-specific preferences and configurations
{ config, ... }:
{
  system.defaults.CustomUserPreferences = {
    # SwiftBar plugin directory
    "com.ameba.SwiftBar" = {
      PluginDirectory = "${config.users.users.hodgesd.home}/Library/Application Support/SwiftBar/Plugins";
    };

    # Add other application-specific preferences here
  };
}
