# Git configuration module
{
  config,
  pkgs,
  lib,
  ...
}: {
  # diff-so-fancy moved to its own HM module in 25.11; enableGitIntegration
  # replaces the old implicit wiring via programs.git.diff-so-fancy.
  programs.diff-so-fancy = {
    enable = true;
    enableGitIntegration = true;
  };

  programs.git = {
    enable = true;
    userEmail = "hodgesd@gmail.com";
    userName = "Derrick Hodges";
    lfs.enable = true;
    extraConfig =
      {
        init.defaultBranch = "main";
        merge = {
          conflictStyle = "diff3";
          tool = "meld";
        };
        pull.rebase = true;
      }
      # Darwin-only: this profile path doesn't exist on NixOS, which ships
      # its own CA bundle and needs no override.
      // lib.optionalAttrs pkgs.stdenv.isDarwin {
        http.sslCAinfo = "/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt";
      };
  };
}
