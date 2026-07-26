# https://afd.hdgs.me — custom-domain alias for the tailnet. The
# public A record points at this host's tailnet IP (unroutable from
# the internet), so reachability stays tailnet-only; only the NAME is
# public. Cert via Let's Encrypt DNS-01 (the host isn't publicly
# reachable, so HTTP-01 can't work) using a Cloudflare API token
# scoped to the hdgs.me zone (sops secret, decrypted at activation).
{config, ...}: {
  security.acme = {
    acceptTerms = true; # LE Subscriber Agreement — user consented 2026-07-25
    defaults.email = "hodgesd@gmail.com";
    certs."afd.hdgs.me" = {
      dnsProvider = "cloudflare";
      environmentFile = config.sops.secrets.cloudflare-acme-env.path;
      group = "nginx";
    };
  };

  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    virtualHosts."afd.hdgs.me" = {
      forceSSL = true;
      useACMEHost = "afd.hdgs.me";
      locations."/".proxyPass = "http://127.0.0.1:8000";
    };
  };
}
