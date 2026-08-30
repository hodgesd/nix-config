# Phase 2: UniFi read-only observability.
#
# Three consumers of one View-Only console account (hermes-viewer):
#  - mcp-unifi: lean MCP server (unifi-mcp/server.py) on 127.0.0.1:9101,
#    hermes's on-demand eyes. First real consumer of the Phase-0
#    majordouble.mcpServers hardening.
#  - unifi-device-watch: 15-min timer, alerts on never-seen MACs.
#  - wan-watch: 1-min external-anchor probes — deliberately does NOT use
#    the console (detects flaps even when the gateway UI is down) and
#    needs no credentials at all.
#
# Auth is username/password (not an API key) because UniFi hides API-key
# creation from View-Only admins — and the account's ROLE is what makes
# this read-only at the account layer, not the credential type. The
# password lives in the sops unifi-hermes-key dotenv; keep that account
# MFA-free and local-only.
#
# Layering note: hermes (UID-jailed by hermes-egress.nix, LAN rejected)
# reaches only 127.0.0.1:9101; the MCP server and watcher run as their
# own DynamicUsers, so their LAN/console egress is unaffected — exactly
# the per-workload split the Phase 0.5 design intended.
#
# Disable: remove ./unifi.nix from default.nix imports. Revoke: delete
# the hermes-viewer account on the console.
{
  config,
  lib,
  pkgs,
  ...
}: let
  pythonEnv = pkgs.python3.withPackages (ps: [ps.fastmcp ps.httpx]);
  consoleUrl = "https://192.168.1.1";
  consoleCert = ./unifi-mcp/console-cert.pem;
  ntfyAlerts = "https://ntfy.jaguar-duckbill.ts.net/hermes-alerts";
  curl = lib.getExe pkgs.curl;
in {
  sops.secrets.unifi-hermes-key.restartUnits = ["mcp-unifi.service"];

  # ── The MCP server ──────────────────────────────────────────────────
  majordouble.mcpServers.unifi = {
    description = "UniFi read-only MCP server (View-Only account, pinned cert)";
    command = "${pythonEnv}/bin/python3";
    args = ["${./unifi-mcp/server.py}" consoleUrl "${consoleCert}"];
    environmentFile = config.sops.secrets.unifi-hermes-key.path;
    readWritePaths = []; # read-only integration: writes nowhere
  };

  # Hermes parks an MCP server after 3 failed connects and won't retry
  # until asked — so make sure the server is up before the gateway starts
  # (observed: a deploy restarting both raced, and hermes parked unifi).
  systemd.services.hermes-agent = {
    after = ["mcp-unifi.service"];
    wants = ["mcp-unifi.service"];
  };

  # Hermes side: the client allowlist mirrors the server's whole catalog.
  # Defense-in-depth only — the server has nothing else to expose.
  services.hermes-agent.mcpServers.unifi = {
    url = "http://127.0.0.1:9101/mcp/";
    tools.include = [
      "wan_health"
      "list_devices"
      "list_clients"
      "recent_events"
      "network_stats"
    ];
  };

  # ── New-device alert ────────────────────────────────────────────────
  systemd.services.unifi-device-watch = {
    description = "Alert on never-seen client MACs via ntfy";
    serviceConfig = {
      Type = "oneshot";
      DynamicUser = true;
      StateDirectory = "unifi-device-watch";
      EnvironmentFile = config.sops.secrets.unifi-hermes-key.path;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      PrivateTmp = true;
      ExecStart = lib.escapeShellArgs [
        "${pythonEnv}/bin/python3"
        "${./unifi-mcp/device_watch.py}"
        consoleUrl
        "${consoleCert}"
        "/var/lib/unifi-device-watch"
        ntfyAlerts
      ];
    };
  };
  systemd.timers.unifi-device-watch = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "10m";
      OnUnitActiveSec = "15m";
    };
  };

  # ── WAN watcher: credential-free flap detection ─────────────────────
  # 2-of-3 anchors must fail to call it DOWN (one flaky anchor isn't an
  # outage). The third anchor is a hostname, so DNS breakage counts as
  # WAN trouble — that's a feature. Transitions append to events.log
  # with duration; ntfy on both edges (down = urgent).
  systemd.services.wan-watch = {
    description = "WAN flap detector (external anchors, no credentials)";
    serviceConfig = {
      Type = "oneshot";
      DynamicUser = true;
      StateDirectory = "wan-watch";
      PrivateTmp = true;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
    };
    script = ''
      set -u
      ok=0
      for target in https://1.1.1.1 https://8.8.8.8 https://api.telegram.org; do
        ${curl} -fsS -m 5 -o /dev/null "$target" 2>/dev/null && ok=$((ok + 1)) || true
      done
      now=down; [ "$ok" -ge 2 ] && now=up

      state="$STATE_DIRECTORY/state"
      log="$STATE_DIRECTORY/events.log"
      prev=$(cat "$state" 2>/dev/null || echo up)

      notify() {
        ${curl} -fsS -m 10 -H "Title: $1" -H "Priority: $2" -H "Tags: $3" \
          -d "$4" ${lib.escapeShellArg ntfyAlerts} >/dev/null || true
      }

      if [ "$now" != "$prev" ]; then
        ts=$(date -Iseconds)
        if [ "$now" = down ]; then
          date +%s > "$STATE_DIRECTORY/down_since"
          echo "$ts DOWN" >> "$log"
          # Best-effort: if the WAN is truly down this can't send either —
          # the recovery message carries the duration for the record.
          notify "WAN is DOWN" urgent rotating_light \
            "External anchors unreachable from nixos-infra at $ts."
        else
          dur=$(( $(date +%s) - $(cat "$STATE_DIRECTORY/down_since" 2>/dev/null || date +%s) ))
          echo "$ts UP after ''${dur}s" >> "$log"
          notify "WAN recovered" default white_check_mark \
            "Outage lasted ''${dur}s (ended $ts)."
        fi
      fi
      echo "$now" > "$state"
    '';
  };
  systemd.timers.wan-watch = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "2m";
      OnUnitActiveSec = "1m";
    };
  };

  # ── Weekly WAN summary (Sunday 08:00 local) ─────────────────────────
  systemd.services.wan-weekly-summary = {
    description = "Weekly WAN flap summary via ntfy";
    serviceConfig = {
      Type = "oneshot";
      DynamicUser = true;
      # Shares wan-watch's state dir read-only via StateDirectory would
      # collide ownership; read the log path directly instead.
      ReadOnlyPaths = ["/var/lib/wan-watch"];
      PrivateTmp = true;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
    };
    script = ''
      set -u
      log=/var/lib/wan-watch/events.log
      cutoff=$(date -d '7 days ago' +%s)
      downs=0; secs=0
      if [ -r "$log" ]; then
        while read -r ts rest; do
          t=$(date -d "$ts" +%s 2>/dev/null || echo 0)
          [ "$t" -ge "$cutoff" ] || continue
          case "$rest" in
            DOWN*) downs=$((downs + 1)) ;;
            UP*) s=''${rest##*after }; s=''${s%s}; secs=$((secs + s)) ;;
          esac
        done < "$log"
      fi
      ${curl} -fsS -m 10 -H "Title: WAN weekly summary" -H "Tags: bar_chart" \
        -d "Last 7 days: $downs outage(s), $((secs / 60)) min total downtime." \
        ${lib.escapeShellArg ntfyAlerts} >/dev/null || true
    '';
  };
  systemd.timers.wan-weekly-summary = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "Sun 08:00";
      Persistent = true;
    };
  };
}
