# Eza configuration module
{
  config,
  pkgs,
  lib,
  ...
}: {
  programs.eza = {
    enable = true;
  };
}
