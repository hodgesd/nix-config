# hosts/common/darwin/dock-presets.nix
# Predefined dock configurations for different use cases
{
  # Full developer setup - for primary development machines
  developer = [
    "/Applications/Firefox.app"
    "/Applications/Google Chrome.app"
    "/Applications/Telegram.app"
    "/Applications/Obsidian.app"
    "/Applications/Visual Studio Code.app"
    "/Applications/OBS.app"
    "/Applications/Ghostty.app"
    "/Applications/iTerm.app"
  ];

  # Minimal setup - for server/headless machines
  minimal = [
    "/Applications/Google Chrome.app"
    "/Applications/Ghostty.app"
  ];

  # Base apps that might be shared across configurations
  base = [
    "/Applications/Obsidian.app"
    "/Applications/Ghostty.app"
  ];

  # Example: productivity-focused setup
  productivity = [
    "/Applications/Obsidian.app"
    "/Applications/Fantastical.app"
    "/Applications/Discord.app"
    "/Applications/Warp.app"
  ];
}
