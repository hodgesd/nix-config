# Off-site dead-man switch for this VM, via healthchecks.io.
#
# Everything that monitors the homelab lives in the homelab: Gatus runs on
# this VM and alerts through ntfy, which also runs on this VM. So none of
# it can tell you the VM is dead, the power is out, or the internet is
# down — the monitor shares a fate with what it watches. This closes that
# gap from outside: every 5 minutes the VM fetches a private healthchecks.io
# URL ("checking in"). If the check-ins stop, healthchecks.io alerts through
# its own channels (email, ntfy.sh, …), none of which depend on this house.
#
# Configure the check as period 5 min / grace 5 min → an alert ~10 min
# after the VM goes silent. The ping URL is the credential (anyone holding
# it can keep the check green), hence sops.
#
# A second check (hc-ntfy) covers ntfy itself: Gatus sends its alerts
# through ntfy, so a dead ntfy is a silent ntfy. Every 5 minutes the VM
# asks ntfy's /v1/health through its tailnet name (sidecar, TLS, app) and
# pings a separate healthchecks.io check only when ntfy says healthy.
# Configure it as period 5 min / grace 10 min: the longer grace rides out
# a container recreate during a deploy, so an alert means ntfy has been
# down ~15 min. If the whole VM dies, both checks alert.
#
# Disable: remove ./healthchecks.nix from default.nix imports and deploy;
# then pause or delete the checks on healthchecks.io so they don't alert.
# (hc-ntfy alone: delete its service + timer below, deploy, delete that check.)
{
  config,
  lib,
  pkgs,
  ...
}: {
  # Dotenv: HC_PING_URL=https://hc-ping.com/<uuid> (VM heartbeat) and
  # HC_NTFY_PING_URL=https://hc-ping.com/<uuid> (ntfy check). The
  # timer-driven oneshots re-read this on every run, so no restartUnits is
  # needed, and an empty or missing value is a harmless no-op.
  sops.secrets.healthchecks-env = {};

  systemd.services.hc-heartbeat = {
    description = "Heartbeat to healthchecks.io (off-site dead-man for this VM)";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      DynamicUser = true;
      # Read by systemd as root before dropping privileges (the secret is
      # root-only 0400), same as every other EnvironmentFile on this host.
      EnvironmentFile = config.sops.secrets.healthchecks-env.path;
    };
    script = ''
      if [ -z "''${HC_PING_URL:-}" ]; then
        echo "HC_PING_URL is empty in the healthchecks-env secret; not checking in" >&2
        exit 0
      fi
      # --retry rides out a brief WAN blip; a sustained outage should be
      # what healthchecks.io sees, and that is the point.
      ${lib.getExe pkgs.curl} -fsS -m 10 --retry 3 --retry-delay 5 "$HC_PING_URL" >/dev/null
    '';
  };

  systemd.timers.hc-heartbeat = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "2m";
      OnUnitActiveSec = "5m";
    };
  };

  systemd.services.hc-ntfy = {
    description = "Ping healthchecks.io while ntfy is healthy (alerts about the alerter)";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      DynamicUser = true;
      EnvironmentFile = config.sops.secrets.healthchecks-env.path;
    };
    script = ''
      # Through the tailnet name, like Gatus: exercises MagicDNS, the
      # ts-ntfy sidecar's TLS and the app, not just the container.
      if ! health=$(${lib.getExe pkgs.curl} -fsS -m 10 --retry 2 --retry-delay 5 \
          https://ntfy.jaguar-duckbill.ts.net/v1/health); then
        echo "ntfy health request failed; not checking in" >&2
        exit 1
      fi
      if ! printf '%s' "$health" | ${lib.getExe pkgs.jq} -e '.healthy == true' >/dev/null; then
        echo "ntfy reports unhealthy ($health); not checking in" >&2
        exit 1
      fi
      if [ -z "''${HC_NTFY_PING_URL:-}" ]; then
        echo "ntfy healthy, but HC_NTFY_PING_URL is empty in the healthchecks-env secret; not checking in" >&2
        exit 0
      fi
      ${lib.getExe pkgs.curl} -fsS -m 10 --retry 3 --retry-delay 5 "$HC_NTFY_PING_URL" >/dev/null
      echo "ntfy healthy; checked in"
    '';
  };

  systemd.timers.hc-ntfy = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "3m";
      OnUnitActiveSec = "5m";
    };
  };
}
