# hosts/common/darwin/aerospace.nix
{
  config,
  pkgs,
  lib,
  ...
}: {
  home-manager.users.${config.majordouble.user} = {
    home.file.".aerospace.toml".source = ./aerospace.toml;
  };
}
