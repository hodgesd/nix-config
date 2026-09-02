# Hermes sentinel: the alerts the first three days of operation were
# missing. The existing watchdogs only check that PROCESSES are alive;
# two real failures (bridge tokens clobbered → 401s for a day; the
# morning brief composed then silently dropped, twice) were invisible to
# them. This timer checks OUTCOMES:
#
#   bridge-vault / bridge-apple  the mini bridges answer their auth wall
#                                (HTTP 401 == healthy: reachable AND
#                                auth enforced; anything else is down)
#   unit-mcp-unifi / unit-mcp-fastmail  VM-local MCP servers active
#                                (a revoked Fastmail token shows up here
#                                as a crash-loop)
#   brief                        after 05:40 local: today's morning-brief
#                                produced its output file AND the gateway
#                                logged no "no delivery target" warning
#   backup-vm                    the nightly homelab-backup didn't fail
#
# Edge-triggered per check (flag file in the state dir): one alert on
# failure, one on recovery, silence otherwise — same discipline as
# kuma-watchdog.nix. Read-only everywhere; no credentials.
#
# Disable: remove ./hermes-sentinel.nix from the host imports.
{
  lib,
  pkgs,
  config,
  ...
}: let
  ntfy = "https://ntfy.jaguar-duckbill.ts.net/hermes-alerts";
  curl = lib.getExe pkgs.curl;
  dockerPkg = config.virtualisation.docker.package;
in {
  systemd.services.hermes-sentinel = {
    description = "Hermes outcome sentinel (bridges, MCP units, brief delivery, backup)";
    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "hermes-sentinel";
    };
    path = [pkgs.coreutils pkgs.gnugrep pkgs.findutils pkgs.systemd dockerPkg];
    script = ''
      set -u
      notify() { # title priority tags body
        ${curl} -fsS -m 10 -H "Title: $1" -H "Priority: $2" -H "Tags: $3" \
          -d "$4" ${lib.escapeShellArg ntfy} >/dev/null || true
      }
      # report <check> <ok|fail> <detail> — alerts only on state change.
      report() {
        flag="$STATE_DIRECTORY/$1.down"
        if [ "$2" = fail ]; then
          if [ ! -e "$flag" ]; then
            notify "Hermes: $1 FAILED" high warning "$3"
            touch "$flag"
          fi
        else
          if [ -e "$flag" ]; then
            notify "Hermes: $1 recovered" default white_check_mark "$3"
            rm -f "$flag"
          fi
        fi
      }

      # Bridges: 401 means reachable + auth wall up. Timeouts/000/5xx = down.
      for b in vault:8321 apple:8322; do
        name=''${b%%:*}; port=''${b##*:}
        code=$(${curl} -s -o /dev/null -m 12 -w '%{http_code}' \
          "https://mini.jaguar-duckbill.ts.net:$port/mcp/" || echo 000)
        if [ "$code" = 401 ]; then
          report "bridge-$name" ok "mini:$port answering again (HTTP 401)."
        else
          report "bridge-$name" fail "mini:$port returned HTTP $code (expected 401). Mini down, serve off, or agent hung?"
        fi
      done

      # VM-local MCP servers.
      for u in mcp-unifi mcp-fastmail; do
        if systemctl is-active --quiet "$u.service"; then
          report "unit-$u" ok "$u.service active again."
        else
          report "unit-$u" fail "$u.service is $(systemctl is-active "$u.service" || true) — check journalctl -u $u (revoked token? crash-loop?)."
        fi
      done

      # Morning brief: judged once the 05:30 run has had time to finish.
      if [ "$(date +%H%M)" -ge 0540 ]; then
        today=$(date +%F)
        out=$(find /var/lib/hermes/.hermes/cron/output -name "''${today}_05-*.md" 2>/dev/null | head -1)
        dropped=$(docker logs --since "''${today}T05:25:00" hermes-agent 2>&1 \
          | grep -c "no delivery target" || true)
        if [ -n "$out" ] && [ "$dropped" = 0 ]; then
          report brief ok "Morning brief for $today ran and delivered."
        elif [ -z "$out" ]; then
          report brief fail "No morning-brief output for $today — the 05:30 job did not run. Check hermes cron list / gateway health."
        else
          report brief fail "Morning brief for $today was composed but NOT delivered (no delivery target). Recreate the job with --deliver telegram:<chat_id>."
        fi
      fi

      # Nightly VM backup result.
      if systemctl is-failed --quiet homelab-backup.service; then
        report backup-vm fail "homelab-backup.service failed — journalctl -u homelab-backup."
      else
        report backup-vm ok "homelab-backup.service healthy again."
      fi
    '';
  };

  systemd.timers.hermes-sentinel = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "5m";
      OnUnitActiveSec = "10m";
    };
  };
}
