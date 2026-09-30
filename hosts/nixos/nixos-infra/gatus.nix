# Gatus — the homelab's monitor and status page, https://status.jaguar-duckbill.ts.net.
# Replaced Uptime Kuma on 2026-09-06 after a side-by-side trial; the
# inventory, mapping and comparison are in docs/GATUS-EVAL.md.
#
# Shape: a native systemd service (upstream services.gatus module) fronted
# by a Tailscale sidecar container (ts-status in stacks/homelab) that gives
# it a tailnet name and a Let's Encrypt cert, the same way Actual Budget
# and the other containers are exposed. Because Gatus is native rather
# than a container sharing the sidecar's network namespace, two things the
# other sidecars don't need appear below: the sidecar reaches Gatus over
# Docker's bridge (hence the firewall rule) and its serve.json proxies to
# host.docker.internal instead of loopback (declared via sidecars.nix).
#
# What Gatus cannot see from here is this VM dying — it shares the VM's
# fate, and so does ntfy. healthchecks.nix covers that from outside.
#
# ICMP checks: the upstream module already grants CAP_NET_RAW via
# AmbientCapabilities + CapabilityBoundingSet (see
# nixos/modules/services/monitoring/gatus.nix in nixpkgs). That is the one
# slice of root needed to open raw sockets for ping; the process otherwise
# runs as an unprivileged DynamicUser with NoNewPrivileges. Nothing to add.
#
# Disable: remove ./gatus.nix from default.nix imports and the ts-status
# service from stacks/homelab/docker-compose.yml, deploy. State to delete
# afterwards: /var/lib/private/gatus and /srv/homelab/ts-status (the
# sidecar's tailnet identity — also remove the node in the admin console).
{
  config,
  lib,
  ...
}: let
  ntfy = "https://ntfy.jaguar-duckbill.ts.net";
  statusUrl = "https://status.jaguar-duckbill.ts.net";

  # Accept any 2xx, following redirects (adguard answers 302 → 200).
  http2xx = ["[STATUS] >= 200" "[STATUS] < 300"];

  # One alert channel for everything; thresholds come from default-alert.
  alerts = [{type = "ntfy";}];

  # 60 s interval, 45 s timeout. "Retries" are the alert's
  # failure-threshold of 3: three consecutive failures before paging.
  http = group: name: url: extraConditions: {
    inherit group name url alerts;
    interval = "60s";
    client.timeout = "45s";
    conditions = http2xx ++ extraConditions;
  };

  # Same 45 s timeout as http: ping's default is 10 s, which a tailnet
  # path relayed through DERP instead of direct can intermittently exceed
  # and page on a healthy box.
  icmp = group: name: host: {
    inherit group name alerts;
    url = "icmp://${host}";
    interval = "60s";
    client.timeout = "45s";
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
      # /var/lib/private/gatus because of DynamicUser). Deliberately not
      # backed up: it is only check history, and the config is this file.
      storage = {
        type = "sqlite";
        path = "/var/lib/gatus/data.db";
        caching = true;
      };

      ui = {
        title = "Homelab | Gatus";
        # Groups are boxes (below); opening grouped means each section
        # header answers "is this machine OK?" at a glance.
        default-sort-by = "group";
      };

      # ntfy is tailnet-only, so the topic name isn't really a secret, but
      # it lives in sops alongside the heartbeat token for tidiness.
      # priority is ntfy's 1-5 scale; a string here crashes Gatus at start.
      alerting.ntfy = {
        url = ntfy;
        topic = "\${GATUS_NTFY_TOPIC}";
        priority = 4;
        click = statusUrl;
        default-alert = {
          failure-threshold = 3;
          success-threshold = 2;
          send-on-resolved = true;
        };
      };

      # One group per box being watched.
      endpoints =
        [
          # The always-on Mac (Hermes bridges). Reachability only; its
          # services are checked by the sentinel in hermes-sentinel.nix.
          # failure-threshold 5 (vs the default 3) because this is a
          # reachability-only ping over the tailnet; a real outage is still
          # paged, just after ~5 min instead of ~3.
          ((icmp "mini" "ping" "100.122.244.86")
            // {
              alerts = [
                {
                  type = "ntfy";
                  failure-threshold = 5;
                }
              ];
            })
          # UNAS Pro 8 on the LAN — backup and Data share target.
          (icmp "nas" "ping" "192.168.1.142")
          # Home Assistant Yellow — the house. A separate box, so unlike the
          # VM's own services Gatus can genuinely observe it dying; no
          # dead-man needed. Both checks deliberately go over the tailnet:
          # they exercise the Tailscale add-on, the only remote path to the
          # box. Plain HTTP on :8123 on purpose — the tailnet is WireGuard-
          # encrypted end to end, and the add-on's Tailscale Serve (HTTPS on
          # 443) failed to start in 0.30.0 so it is left disabled; see
          # docs/HOME-ASSISTANT.md. /manifest.json answers 200 without auth,
          # so no long-lived HA token has to live in sops just to monitor it.
          (icmp "yellow" "ping" "100.100.120.31")
          (http "yellow" "home-assistant" "http://homeassistant.jaguar-duckbill.ts.net:8123/manifest.json" [])
          # This VM's services, all through their tailnet/public names so
          # DNS, the sidecar, TLS and the app are exercised together.
          (http "nixos-infra" "actual-budget" "https://budget.jaguar-duckbill.ts.net" [])
          (http "nixos-infra" "ntfy" "http://ntfy.jaguar-duckbill.ts.net/dashboard" [])
          (http "nixos-infra" "adguard" "https://adguard.jaguar-duckbill.ts.net" [])
          (http "nixos-infra" "homepage" "https://homepage.jaguar-duckbill.ts.net" [])
          (http "nixos-infra" "librespeed" "https://librespeed.jaguar-duckbill.ts.net" ["[CERTIFICATE_EXPIRATION] > 72h"])
          (http "nixos-infra" "metube" "https://metube.jaguar-duckbill.ts.net" [])
        ]
        # Every sidecar declared in sidecars.nix with a gatus name
        # (changedetection, stirling-pdf, drawio, ...).
        ++ lib.mapAttrsToList
        (name: s: http "nixos-infra" s.gatus "https://${name}.jaguar-duckbill.ts.net" s.conditions)
        (lib.filterAttrs (_: s: s.gatus != null) config.homelab.sidecars)
        ++ [
          # hn-summaries is native with no sidecar, so its tailnet name goes
          # straight to the port (8090, set in hn-summaries.nix). [BODY].ok
          # proves the app answered, not just that the socket is open.
          (http "nixos-infra" "hn-summaries" "http://nixos-infra-1.jaguar-duckbill.ts.net:8090/healthz" ["[BODY].ok == true"])
          # Public name: DNS + nginx + the LE cert + the app in one poll.
          (http "nixos-infra" "easy-afd" "https://afd.hdgs.me/healthz" [])
        ];

      # Dead-man switch for the weekly Easy A/FD data refresh. The refresh
      # script in easy-afd.nix POSTs here on success (bearer token from the
      # shared GATUS_REFRESH_TOKEN); no POST for 192 h means the rebuild
      # failed or never ran and the app is serving stale aeronautical data.
      # Key derived by Gatus from group + name: nixos-infra_easy-afd-refresh.
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

  # ts-status's serve.json (sidecars.nix). host.docker.internal is the
  # compose-provided name for "the VM itself". Not self-monitored: Gatus
  # polling its own status page would only ever say "up".
  homelab.sidecars.status = {
    upstream = "http://host.docker.internal:8080";
    gatus = null;
  };
}
