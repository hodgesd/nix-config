# Reciprocal watchdog: the VM watches Uptime Kuma, which now lives on the
# mini and watches the VM.
#
# Moving Kuma off this host fixed the problem that it couldn't report its
# own host dying. It created the mirror-image problem: nothing notices when
# Kuma itself is down, and a dead Kuma looks exactly like "everything is
# fine" — no alerts either way. This closes that loop.
#
# The alert path deliberately does NOT route through Kuma. It posts
# straight to the ntfy instance in the homelab stack, so it still fires
# when Kuma is precisely what's broken. Both endpoints are tailnet nodes
# and this host has tailscale0, so no new networking is involved.
#
# Note the blind spot this cannot cover: the two boxes now watch each
# other, so a power or internet outage that takes down both silences both.
# Covering that needs a third party off-site.
{
  config,
  lib,
  pkgs,
  ...
}: let
  # Kuma's own URL, unchanged by the move — the sidecar kept `hostname:
  # uptime`, which is also why the push-monitor tokens survived.
  kumaUrl = "https://uptime.jaguar-duckbill.ts.net/";

  # ntfy is tailnet-only (nothing listens on the LAN but SSH), so the topic
  # name isn't a secret and doesn't need sops. Subscribe with:
  #   ntfy subscribe https://ntfy.jaguar-duckbill.ts.net/kuma-watchdog
  ntfyUrl = "https://ntfy.jaguar-duckbill.ts.net/kuma-watchdog";

  curl = lib.getExe pkgs.curl;
in {
  systemd.services.kuma-watchdog = {
    description = "Watch Uptime Kuma on the mini, alert via ntfy";
    serviceConfig = {
      Type = "oneshot";
      # Holds the flag file that makes alerting edge-triggered.
      StateDirectory = "kuma-watchdog";
    };
    script = ''
      set -u
      flag="$STATE_DIRECTORY/down"

      notify() {
        ${curl} -fsS -m 10 \
          -H "Title: $1" \
          -H "Priority: $2" \
          -H "Tags: $3" \
          -d "$4" \
          ${lib.escapeShellArg ntfyUrl} >/dev/null || true
      }

      # --retry rides out a container restart or a brief tailnet blip;
      # only a sustained failure should page.
      if ${curl} -fsS -o /dev/null -m 10 --retry 2 --retry-delay 5 \
        ${lib.escapeShellArg kumaUrl}; then
        if [ -e "$flag" ]; then
          notify "Uptime Kuma recovered" default white_check_mark \
            "Kuma on the mini is reachable again."
          rm -f "$flag"
        fi
      else
        # Edge-triggered: alert once per outage, not every 5 minutes.
        if [ ! -e "$flag" ]; then
          notify "Uptime Kuma is DOWN" urgent rotating_light \
            "${kumaUrl} unreachable from nixos-infra. Monitoring is blind until this is back."
          touch "$flag"
        fi
      fi
    '';
  };

  systemd.timers.kuma-watchdog = {
    wantedBy = ["timers.target"];
    timerConfig = {
      # Generous OnBootSec: if both boxes come back from the same power
      # cut, the mini needs time to boot, auto-login and start OrbStack
      # before its absence means anything.
      OnBootSec = "10m";
      OnUnitActiveSec = "5m";
      Persistent = true;
    };
  };
}
