# Environment variables and session settings
{
  config,
  pkgs,
  lib,
  ...
}: {
  home.sessionVariables = {
    NIX_SSL_CERT_FILE = "/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt";
  };
}
