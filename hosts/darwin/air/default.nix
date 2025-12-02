# Host-specific configuration for air (M1 Laptop)
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
