# hosts/common/darwin/defaults/apps.nix
# Application-specific preferences and configurations
{...}: {
  system.defaults.CustomUserPreferences = {
    # Add application-specific preferences here
    # Note: SwiftBar plugin directory is managed by home-manager (home/swiftbar/swiftbar.nix)
  };
}
