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
# Disable: remove ./healthchecks.nix from default.nix imports and deploy;
# then pause or delete the check on healthchecks.io so it doesn't alert.
{
  config,
  lib,
  pkgs,
  ...
}: {
  # One line: HC_PING_URL=https://hc-ping.com/<uuid>. The timer-driven
  # oneshot re-reads this on every run, so no restartUnits is needed and
  # an empty value (before the account exists) is a harmless no-op.
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
}
