# Environment variables and session settings
{
  config,
  pkgs,
  lib,
  ...
}: {
  # Darwin-only: this profile path doesn't exist on NixOS, which ships its
  # own CA bundle at /etc/ssl/certs and needs no override.
  home.sessionVariables = lib.optionalAttrs pkgs.stdenv.isDarwin {
    NIX_SSL_CERT_FILE = "/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt";
  };
}
