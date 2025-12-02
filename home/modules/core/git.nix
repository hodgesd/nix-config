# Git configuration module
{
  config,
  pkgs,
  lib,
  ...
}: {
  programs.git = {
    enable = true;
    userEmail = "hodgesd@gmail.com";
    userName = "Derrick Hodges";
    diff-so-fancy.enable = true;
    lfs.enable = true;
    extraConfig = {
      init.defaultBranch = "main";
      merge = {
        conflictStyle = "diff3";
        tool = "meld";
      };
      pull.rebase = true;
      http.sslCAinfo = "/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt";
    };
  };
}
