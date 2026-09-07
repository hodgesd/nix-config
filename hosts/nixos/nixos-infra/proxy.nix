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

  # Let containers reach this vhost. Homepage's Easy A/FD siteMonitor polls
  # https://afd.hdgs.me/healthz from inside the homelab compose project;
  # the name resolves to this host's tailnet IP, but the packet arrives
  # over the Docker bridge (homelab_default, 172.19.0.0/16), which the
  # firewall does not trust — it trusts tailscale0 only — so the check
  # timed out. Same trap and same fix as Gatus's 8080 rule in gatus.nix:
  # accept 443 from Docker's private range only. The LAN (192.168.1.0/24)
  # stays blocked, so the vhost remains tailnet-only from outside the box.
  networking.firewall.extraCommands = ''
    iptables -A nixos-fw -s 172.16.0.0/12 -p tcp --dport 443 -j nixos-fw-accept
  '';
}
