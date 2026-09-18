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
#   provider / model             the endpoint and model state.db recorded
#                                on the last call match what hermes.nix
#                                declares (added after three weeks of
#                                undetected routing through a provider the
#                                config did not name — see hermes.nix)
#   brief                        after 05:40 local: today's morning-brief
#                                produced its output file AND the gateway
#                                logged no "no delivery target" warning
#   backup-vm                    the nightly homelab-backup didn't fail
#
# Edge-triggered per check (flag file in the state dir): one alert on
# failure, one on recovery, silence otherwise — same discipline as
# hermes.nix's hermes-watchdog. Read-only everywhere; no credentials.
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

  # Read the provider/model the host actually declares, so the drift check
  # below compares against hermes.nix rather than a copy that rots. Both
  # are set in hosts/nixos/nixos-infra/hermes.nix; the defaults are only a
  # guard against evaluating before that module has set them.
  hermesSettings = config.services.hermes-agent.settings or {};
  hermesBaseUrl = hermesSettings.model.base_url or "";
  hermesModel = hermesSettings.model.default or "";
in {
  systemd.services.hermes-sentinel = {
    description = "Hermes outcome sentinel (bridges, MCP units, brief delivery, backup)";
    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "hermes-sentinel";
    };
    path = [pkgs.coreutils pkgs.gnugrep pkgs.findutils pkgs.systemd pkgs.sqlite dockerPkg];
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

      # Provider / model drift. Added 2026-09-17 after discovering that
      # hermes had been billing through openrouter.ai for three weeks
      # while config.yaml declared api.anthropic.com — hermes-agent
      # resolves its provider from .env credentials and silently ignores a
      # model.base_url that disagrees. Nothing caught it because every
      # other check here asks "did the work happen", not "where did it go".
      #
      # This is DRIFT DETECTION, not a jurisdiction gate: it compares what
      # state.db recorded on the most recent call against what hermes.nix
      # declares, and complains when they diverge. Both directions are
      # useful — it catches a silent re-route, and it confirms a
      # deliberate model hop landed (flip model.default, redeploy, watch
      # it go fail → recovered). The declared values are interpolated from
      # the Nix config itself, so they cannot drift from hermes.nix.
      # NB: two columns, no string literals in the SQL — sqlite3 list mode
      # already separates with "|" and renders NULL as empty. Deliberate:
      # a doubled single-quote anywhere in here (even in a comment, since
      # this whole script is one Nix indented string) ends that string.
      db=/var/lib/hermes/.hermes/state.db
      row=$(sqlite3 -readonly "$db" \
        "select billing_base_url, model from session_model_usage order by last_seen desc limit 1;" \
        2>/dev/null || echo "")
      want_url=${lib.escapeShellArg hermesBaseUrl}
      want_model=${lib.escapeShellArg hermesModel}
      if [ -z "$row" ]; then
        report provider fail "Cannot read billing_base_url from $db (missing, locked, or hermes changed the schema). Provider drift is now unmonitored."
      else
        got_url=''${row%%|*}; got_model=''${row##*|}
        if [ "$got_url" = "$want_url" ]; then
          report provider ok "Inference on the declared provider ($got_url)."
        else
          report provider fail "Inference is routing via $got_url, but hermes.nix declares $want_url. Full session context (vault, mail, reminders, terminal) is going somewhere the config does not say."
        fi
        if [ "$got_model" = "$want_model" ]; then
          report model ok "Serving the declared model ($got_model)."
        else
          report model fail "Model is $got_model, but hermes.nix declares $want_model. Deliberate hop? Update model.default so config matches reality."
        fi
      fi

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
