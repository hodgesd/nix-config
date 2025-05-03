{ config, ... }:
{
  system.defaults.dock = {
    persistent-apps = [
#      "/Applications/Telegram.app"
#      "/Applications/Signal.app"
      "/Applications/Discord.app"
      "/Applications/Ivory.app"
      "/Applications/Obsidian.app"
      "/Applications/Fantastical.app"
#      "/Applications/Ghostty.app"
    ];
  };
}
