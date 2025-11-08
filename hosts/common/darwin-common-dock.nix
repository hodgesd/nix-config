{ config, ... }:
{
  system.defaults.dock = {
    persistent-apps = [
      "/Applications/Discord.app"
      "/Applications/Obsidian.app"
      "/Applications/Fantastical.app"
      "/Applications/Warp.app"
    ];
  };
}
