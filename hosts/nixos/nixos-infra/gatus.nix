# Gatus — side-by-side trial against Uptime Kuma (which stays untouched on
# the mini; see stacks/uptime/docker-compose.yml). Every Kuma monitor is
# mirrored here so both tools alert in parallel; docs/GATUS-EVAL.md holds
# the inventory, the mapping, and the comparison.
#
# Shape: a native systemd service (upstream services.gatus module) fronted
# by a Tailscale sidecar container (ts-gatus in stacks/homelab) that gives
# it https://gatus.jaguar-duckbill.ts.net with a Let's Encrypt cert, the
# same way Kuma and Actual Budget are exposed. Because Gatus is native
# rather than a container sharing the sidecar's network namespace, two
# things Kuma never needed appear below: the sidecar reaches Gatus over
# Docker's bridge (hence the firewall rule) and its serve.json is generated
# by nix instead of being hand-made in the stack dir.
#
# ICMP checks: the upstream module already grants CAP_NET_RAW via
# AmbientCapabilities + CapabilityBoundingSet (see
# nixos/modules/services/monitoring/gatus.nix in nixpkgs). That is the one
# slice of root needed to open raw sockets for ping; the process otherwise
# runs as an unprivileged DynamicUser with NoNewPrivileges. Nothing to add.
#
# Disable: remove ./gatus.nix from default.nix imports and the ts-gatus
# service from stacks/homelab/docker-compose.yml, deploy. State to delete
# afterwards: /var/lib/private/gatus and /srv/homelab/ts-gatus (the
# sidecar's tailnet identity — also remove the node in the admin console).
{config, ...}: let
  ntfy = "https://ntfy.jaguar-duckbill.ts.net";
  gatusUrl = "https://gatus.jaguar-duckbill.ts.net";

  # Kuma's accepted status codes are "200-299" on every HTTP monitor.
  http2xx = ["[STATUS] >= 200" "[STATUS] < 300"];

  # One alert channel for everything; thresholds come from default-alert.
  alerts = [{type = "ntfy";}];

  # Kuma defaults: 60 s interval, 48 s timeout (45 s here). Kuma's
  # "retries" has no direct equivalent — the alert's failure-threshold of
  # 3 plays that role for every endpoint.
  http = group: name: url: extraConditions: {
    inherit group name url alerts;
    interval = "60s";
    client.timeout = "45s";
    conditions = http2xx ++ extraConditions;
  };

  icmp = group: name: host: {
    inherit group name alerts;
    url = "icmp://${host}";
    interval = "60s";
    conditions = ["[CONNECTED] == true"];
  };
in {
  # Dotenv blob: GATUS_NTFY_TOPIC, GATUS_REFRESH_TOKEN. Gatus expands
  # ''${VAR} in its YAML at startup, so the rendered config in /nix/store
  # carries only placeholders. restartUnits for the same reason as
  # easy-afd-env (default.nix): systemd doesn't notice EnvironmentFile
  # content changes on its own.
  sops.secrets.gatus-env.restartUnits = ["gatus.service"];

  services.gatus = {
    enable = true;
    environmentFile = config.sops.secrets.gatus-env.path;
    # openFirewall stays false (default): it would open 8080 on the LAN.
    settings = {
      # Binds all interfaces, but the firewall only trusts tailscale0 (plus
      # the Docker-range rule below), so this is tailnet-only — same
      # arrangement as easy-afd on :8000.
      web = {
        address = "0.0.0.0";
        port = 8080;
      };

      # SQLite under the unit's StateDirectory (/var/lib/gatus →
      # /var/lib/private/gatus because of DynamicUser). Not backed up
      # during the trial: it is only check history.
      storage = {
        type = "sqlite";
        path = "/var/lib/gatus/data.db";
        caching = true;
      };

      ui = {
        title = "Homelab | Gatus";
        header = "Homelab";
        buttons = [
          {
            name = "Uptime Kuma";
            link = "https://uptime.jaguar-duckbill.ts.net";
          }
        ];
      };

      # Kuma has no notification providers at all (verified 2026-09-06);
      # homelab alerting is the ntfy watchdog timers. Gatus gets its own
      # topic so trial alerts are easy to tell apart. The topic lives in
      # sops at the user's request, although kuma-watchdog.nix treats
      # topic names as non-secret (ntfy is tailnet-only).
      alerting.ntfy = {
        url = ntfy;
        topic = "\${GATUS_NTFY_TOPIC}";
        priority = 4; # ntfy scale 1-5; 4 = high (a string here fails to parse)
        click = gatusUrl;
        default-alert = {
          failure-threshold = 3;
          success-threshold = 2;
          send-on-resolved = true;
        };
      };

      # Groups are new (Kuma had none); grouped by the host being watched.
      endpoints = [
        (http "nixos-infra" "actual-budget" "https://budget.jaguar-duckbill.ts.net" [])
        (http "nixos-infra" "ntfy" "http://ntfy.jaguar-duckbill.ts.net/dashboard" [])
        (http "nixos-infra" "adguard" "https://adguard.jaguar-duckbill.ts.net" [])
        # The one Kuma monitor with certificate-expiry alerts enabled.
        (http "nixos-infra" "librespeed" "https://librespeed.jaguar-duckbill.ts.net" ["[CERTIFICATE_EXPIRATION] > 72h"])
        # Kuma's afd-healthz is a push dead-man switch because its container
        # couldn't route to the tailnet. Gatus runs on the host, so this is
        # a direct poll of the public name (DNS + nginx + LE cert + app).
        # Trade-off: it can no longer notice the VM itself dying — Kuma on
        # the mini keeps that job.
        (http "nixos-infra" "easy-afd" "https://afd.hdgs.me/healthz" [])
        # Mirrors what kuma-watchdog.nix checks every 5 min.
        (http "mini" "uptime-kuma" "https://uptime.jaguar-duckbill.ts.net/dashboard" [])
        # New checks, not in Kuma — exercise the raw-socket path.
        (icmp "infra" "mini" "100.122.244.86")
        (icmp "infra" "nas" "192.168.1.142")
      ];

      # Kuma's easy-afd-refresh push monitor (8-day window). The refresh
      # script in easy-afd.nix POSTs here on success; no POST for 192 h
      # means the weekly data rebuild failed or never ran. Key derived by
      # Gatus from group + name: nixos-infra_easy-afd-refresh.
      external-endpoints = [
        {
          group = "nixos-infra";
          name = "easy-afd-refresh";
          token = "\${GATUS_REFRESH_TOKEN}";
          heartbeat.interval = "192h";
          inherit alerts;
        }
      ];
    };
  };

  # The sidecar talks to Gatus over the compose project's bridge
  # (homelab_default, 172.19.0.0/16). The firewall trusts tailscale0 only,
  # and Docker bridges are not tailscale0, so without this the proxy gets
  # "connection refused". Scoped to Docker's private range and to 8080;
  # the LAN (192.168.1.0/24) stays blocked.
  networking.firewall.extraCommands = ''
    iptables -A nixos-fw -s 172.16.0.0/12 -p tcp --dport 8080 -j nixos-fw-accept
  '';

  # serve.json for ts-gatus, bind-mounted read-only by the compose file.
  # Both stanzas are required (docs/NIXOS-INFRA.md gotchas): TCP 443 makes
  # the sidecar terminate TLS, Web proxies to the host — host.docker.internal
  # is the compose-provided name for "the VM itself". A change here needs
  # `docker restart ts-gatus`; compose won't restart it for a mount's
  # contents.
  environment.etc."ts-gatus/serve.json".text = builtins.toJSON {
    TCP."443".HTTPS = true;
    Web."\${TS_CERT_DOMAIN}:443".Handlers."/".Proxy = "http://host.docker.internal:8080";
  };
}
