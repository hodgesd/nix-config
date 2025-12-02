# Starship prompt configuration
{
  config,
  pkgs,
  lib,
  ...
}: {
  programs.starship = {
    enable = true;
    settings = import ../../starship/starship.toml;
  };
}
