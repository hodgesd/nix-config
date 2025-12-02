# SSH configuration module
{
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [../../ssh/ssh.nix];
}
