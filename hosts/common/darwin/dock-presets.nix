# hosts/common/darwin/dock-presets.nix
# Predefined dock configurations for different use cases
{
  # Full developer setup - for primary development machines
  developer = [
  ];

  # Minimal setup - for server/headless machines
  minimal = [
  ];

  # Base apps that might be shared across configurations
  base = [
  ];

  # Example: productivity-focused setup
  productivity = [
    "/Applications/Fantastical.app"
    "/Applications/Discord.app"
  ];
}
