# Host-specific configuration for mbp (M3 Pro Laptop)
{machine, ...}: {
  # Enable wallpaper management
  majordouble.wallpaper = {
    enable = true;
    path = "/Users/hodgesd/Documents/Wallpapers/Gulfstream GV at Waimea.jpg";
  };

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

    # Disable wallpaper shuffle/rotation
    "com.apple.dock" = {
      # Disable picture rotation
      desktop-picture-show-debug-text = false;
    };
  };
}
