# AeroSpace configuration file
{
  config,
  pkgs,
  lib,
  ...
}: {
  home.file.".aerospace.toml".source = ./aerospace.toml;
}
