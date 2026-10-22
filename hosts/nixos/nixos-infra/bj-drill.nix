# https://21.hdgs.me — blackjack basic strategy drill. A static PWA
# (one self-contained index.html + service worker + icons) in ./bj-site,
# served straight from the Nix store by the nginx in proxy.nix: no app
# process, no state on the host (progress lives in the browser's
# localStorage), so a deploy is the whole release. Gatus (gatus.nix)
# polls the page.
#
# Same tailnet-only arrangement as afd.hdgs.me (see proxy.nix): the
# public A record points at this host's tailnet IP, and the LE cert
# comes via Cloudflare DNS-01 with the same zone-scoped token.
#
# Editing the app: change bj-site/index.html and bump VERSION in
# bj-site/sw.js, then deploy. Files under bj-site/ must be git-tracked
# or the flake build will not see them.
{config, ...}: {
  security.acme.certs."21.hdgs.me" = {
    dnsProvider = "cloudflare";
    environmentFile = config.sops.secrets.cloudflare-acme-env.path;
    group = "nginx";
  };

  services.nginx.virtualHosts."21.hdgs.me" = {
    forceSSL = true;
    useACMEHost = "21.hdgs.me";
    root = ./bj-site;
    # Revalidate on every load (ETags still answer 304s) so a new sw.js
    # and index.html reach phones that installed the app to the home
    # screen. The whole site is ~90 KB, so this costs nothing.
    extraConfig = ''
      add_header Cache-Control "no-cache" always;
    '';
  };
}
