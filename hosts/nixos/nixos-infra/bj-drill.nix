# https://21.hdgs.me — blackjack basic strategy drill. A static PWA
# (one self-contained index.html + service worker + icons) from the
# bj-drill flake input (github:hodgesd/21), served straight from the Nix
# store by the nginx in proxy.nix, plus its hand log: /api/ proxies to
# bj-drill-api (the repo's server/server.py, Python stdlib + SQLite) on
# loopback. Every answered hand is stored there, and devices sync their
# progress through it (see the app README). The SQLite file lives in
# /var/lib/private/bj-drill (StateDirectory under DynamicUser); backup.nix
# copies it to the NAS nightly because the hand history can't be
# regenerated. Gatus (gatus.nix) polls the page and api/healthz.
#
# Same tailnet-only arrangement as afd.hdgs.me (see proxy.nix): the
# public A record points at this host's tailnet IP, and the LE cert
# comes via Cloudflare DNS-01 with the same zone-scoped token.
#
# Releasing the app: push to github.com/hodgesd/21 (bump VERSION in
# its sw.js), then `nix flake update bj-drill && just deploy`. The lock
# file pins which app commit is live.
{
  config,
  inputs,
  pkgs,
  ...
}: let
  # Loopback only; nginx is the way in. Free port: 8000 easy-afd, 8080
  # gatus, 8090 hn-summaries (ss -ltn on the VM, 2026-10-22).
  apiPort = 8091;
in {
  security.acme.certs."21.hdgs.me" = {
    dnsProvider = "cloudflare";
    environmentFile = config.sops.secrets.cloudflare-acme-env.path;
    group = "nginx";
  };

  services.nginx.virtualHosts."21.hdgs.me" = {
    forceSSL = true;
    useACMEHost = "21.hdgs.me";
    root = inputs.bj-drill;
    # Revalidate on every load (ETags still answer 304s) so a new sw.js
    # and index.html reach phones that installed the app to the home
    # screen. The whole site is ~90 KB, so this costs nothing.
    extraConfig = ''
      add_header Cache-Control "no-cache" always;
    '';
    locations."/api/".proxyPass = "http://127.0.0.1:${toString apiPort}";
  };

  systemd.services.bj-drill-api = {
    description = "Blackjack drill hand log and progress sync";
    wantedBy = ["multi-user.target"];
    after = ["network.target"];
    environment = {
      BJ_DB = "/var/lib/bj-drill/bj-drill.db";
      BJ_HOST = "127.0.0.1";
      BJ_PORT = toString apiPort;
      PYTHONUNBUFFERED = "1";
    };
    startLimitBurst = 5;
    startLimitIntervalSec = 60;
    serviceConfig = {
      DynamicUser = true;
      StateDirectory = "bj-drill";
      ExecStart = "${pkgs.python3}/bin/python3 ${inputs.bj-drill}/server/server.py";
      Restart = "always";
      RestartSec = "5s";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ProtectKernelTunables = true;
      ProtectControlGroups = true;
      RestrictNamespaces = true;
      LockPersonality = true;
      RestrictAddressFamilies = ["AF_INET" "AF_INET6"];
    };
  };
}
