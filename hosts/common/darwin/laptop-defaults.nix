# Power/menu-bar settings common to all laptops; applied via machine.formFactor.
{
  machine,
  lib,
  ...
}:
lib.mkIf (machine.formFactor == "laptop") {
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
