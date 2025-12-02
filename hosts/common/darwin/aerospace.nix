# hosts/common/darwin/aerospace.nix
{
  config,
  pkgs,
  lib,
  username,
  ...
}: {
  home-manager.users.${username} = {
    home.file.".aerospace.toml".source = ./aerospace.toml;
  };
}
