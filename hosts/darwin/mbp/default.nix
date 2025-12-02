# Host-specific configuration for mbp (M3 Pro Laptop)
{machine, ...}: {
  # Laptop-specific power management
  system.defaults.CustomUserPreferences = {
    "com.apple.menuextra.battery" = {
      # Show battery percentage in menu bar
      ShowPercent = "YES";
    };

    "com.apple.BezelServices" = {
      # Keyboard brightness settings for laptop
      kDim = true;
      kDimTime = 300;
    };
  };
}
