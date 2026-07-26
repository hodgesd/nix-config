# Environment variables and session settings
{
  config,
  pkgs,
  lib,
  ...
}: {
  home.sessionVariables =
    {
      # sops looks in ~/Library/Application Support/sops on macOS by default;
      # pin the conventional path so `sops secrets/*.yaml` finds the age key.
      SOPS_AGE_KEY_FILE = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
    }
    # Darwin-only: this profile path doesn't exist on NixOS, which ships its
    # own CA bundle at /etc/ssl/certs and needs no override.
    // lib.optionalAttrs pkgs.stdenv.isDarwin {
      NIX_SSL_CERT_FILE = "/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt";
    };
}
