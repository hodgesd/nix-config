# Easy A/FD (github.com/hodgesd/gvii_afd-backup) as a systemd service:
# the app itself and the daily data refresh. Gatus (gatus.nix) polls
# https://afd.hdgs.me/healthz — for liveness and, separately, for whether
# the data is current — and the refresh reports to it on success and
# pages through it on failure. The nginx/ACME front is proxy.nix; NAS
# backup is backup.nix.
#
# KNOWN GAP (out of scope): source lives in /srv/easy-afd, rsynced from
# the dev Mac over Tailscale (the repo is private so it is not fetched
# at build time). A from-scratch rebuild has a broken easy-afd.service
# until that rsync runs — see docs/NIXOS-INFRA.md.
#
# Mutable data lives in /var/lib/easy-afd: the app opens
# best_apprs.pickle, dtpp_charts.pickle and data/* relative to its
# working directory, and writes *_cache_v2.json weather caches there.
# The two chart pickles exist twice — the repo's committed copies
# (symlinked in by preStart) and the refresh's own copies under data/ —
# and the app loads whichever pair is from the newer d-TPP cycle.
#
# IMPORTANT: never copy data/ from another machine — data/alternates.pickle
# is pandas-version-coupled (dev Mac runs pandas 3.x, nixpkgs ships 2.x).
# The easy-afd-refresh service rebuilds all of data/ locally instead.
#
# Secrets (Autorouter credentials, Gatus heartbeat URL + token) come from sops —
# decrypted to /run/secrets/easy-afd-env at activation; systemd reads the
# EnvironmentFile as root before dropping privileges.
{
  config,
  pkgs,
  lib,
  ...
}: let
  appDir = "/srv/easy-afd";
  stateDir = "/var/lib/easy-afd";

  # Only runtime dep missing from nixpkgs. Pure-py3 wheel (World Magnetic
  # Model), so install the published wheel directly.
  pygeomag = pkgs.python3Packages.buildPythonPackage rec {
    pname = "pygeomag";
    version = "1.1.0";
    format = "wheel";
    src = pkgs.python3Packages.fetchPypi {
      inherit pname version format;
      dist = "py3";
      python = "py3";
      hash = "sha256-sI/F3nylRXIeUR9io0LUFaTXbmlf7CjvnvJV6ZTmcns=";
    };
    pythonImportsCheck = ["pygeomag"];
  };

  # Runtime deps from the repo's pyproject.toml.
  pyEnv = pkgs.python3.withPackages (ps:
    [pygeomag]
    ++ (with ps; [
      beautifulsoup4
      colorama
      flask
      gunicorn
      lxml
      numpy
      pandas
      python-dateutil
      python-dotenv
      requests
      scikit-learn
    ]));

  # Link the repo's committed pickles into the working directory.
  preStart = pkgs.writeShellScript "easy-afd-prestart" ''
    set -eu
    mkdir -p ${stateDir}/data
    ln -sfn ${appDir}/best_apprs.pickle ${stateDir}/best_apprs.pickle
    ln -sfn ${appDir}/dtpp_charts.pickle ${stateDir}/dtpp_charts.pickle
  '';

  # Rebuild the bulk aeronautical data into ${stateDir}/data: NASR and
  # the d-TPP chart index (both on the FAA's 28-day cycle), OurAirports,
  # and the openAIP PCN overlay.
  #
  # Every source is attempted even when an earlier one fails. This was a
  # `set -e` chain, so when the FAA changed the NASR file layout in
  # September 2026 the failing NASR step also skipped OurAirports and
  # openAIP — for the five weeks it took anyone to notice. A failed
  # source still fails the unit (which is what pages, see onFailure
  # below); it just no longer takes the others down with it.
  refresh = pkgs.writeShellScript "easy-afd-refresh" ''
    set -u
    cd ${stateDir}
    py=${pyEnv}/bin/python
    scripts=${appDir}/scripts
    data=${stateDir}/data
    failed=""
    step() { # name command...
      name=$1
      shift
      if "$@"; then
        echo "refresh ok: $name"
      else
        # Worded for notify-failure@ (gatus.nix), which pages with the
        # lines of this run that look like errors.
        echo "REFRESH FAILED: $name (exit $?)" >&2
        failed="$failed $name"
      fi
    }
    step nasr "$py" "$scripts/refresh_faa_data.py" --nasr --data-dir "$data"
    # The chart index and best-approach table. Until 2026-10 these came
    # only from the repo's committed pickles, so they were as old as the
    # last commit that refreshed them (four cycles, when it was found).
    step charts "$py" "$scripts/refresh_faa_data.py" --dtpp --dtpp-out "$data"
    step ourairports "$py" "$scripts/refresh_ourairports_data.py" --data-dir "$data"
    # Non-fatal: needs OPENAIP_API_KEY (in the easy-afd-env secret) since
    # openAIP's bulk exports went requester-pays (2026-07-22); on any
    # failure the PCN overlay just goes stale and the app degrades
    # gracefully without it.
    "$py" "$scripts/refresh_openaip_data.py" --data-dir "$data" \
      || echo "openaip refresh failed (non-fatal)" >&2
    if [ -n "$failed" ]; then
      echo "REFRESH FAILED:$failed" >&2
      exit 1
    fi
    # Success heartbeat to the Gatus external endpoint (36 h window;
    # hosts/nixos/nixos-infra/gatus.nix): a POST with a bearer token. Both
    # GATUS_* values live in the easy-afd-env secret; skipped when unset.
    if [ -n "''${GATUS_REFRESH_PUSH_URL:-}" ]; then
      ${pkgs.curl}/bin/curl -fsS -m 10 --retry 3 -X POST \
        -H "Authorization: Bearer ''${GATUS_REFRESH_TOKEN:-}" \
        "''${GATUS_REFRESH_PUSH_URL}" >/dev/null \
        || echo "gatus heartbeat push failed" >&2
    fi
  '';

  hardening = {
    NoNewPrivileges = true;
    PrivateTmp = true;
    ProtectSystem = "strict"; # everything RO except StateDirectory
    ProtectHome = true;
    ProtectKernelTunables = true;
    ProtectControlGroups = true;
    RestrictNamespaces = true;
    LockPersonality = true;
  };
in {
  users.users.easy-afd = {
    isSystemUser = true;
    group = "easy-afd";
    home = stateDir;
  };
  users.groups.easy-afd = {};

  systemd.services.easy-afd = {
    description = "Easy A/FD web app";
    wantedBy = ["multi-user.target"];
    after = ["network-online.target"];
    wants = ["network-online.target"];
    environment.PYTHONPATH = appDir;

    # Unit-level, NOT serviceConfig: systemd moved the start-rate limit
    # to [Unit] in v229, so setting these under [Service] is silently
    # ignored. Defaults are 5 starts / 10 s, which RestartSec below
    # would blow through in under a second — the app would then stay
    # down permanently, which is the opposite of what Restart=always is
    # for.
    startLimitBurst = 5;
    startLimitIntervalSec = 60;

    serviceConfig =
      hardening
      // {
        User = "easy-afd";
        Group = "easy-afd";
        StateDirectory = "easy-afd";
        WorkingDirectory = stateDir;
        # Runs as the service user — StateDirectory is owned by it, and root
        # ownership here would break the refresh service's writes.
        ExecStartPre = preStart;
        # Mirrors the repo's serve.sh. Binds all interfaces, but the firewall
        # only trusts tailscale0, so this is tailnet-only.
        ExecStart = lib.concatStringsSep " " [
          "${pyEnv}/bin/gunicorn"
          "--bind 0.0.0.0:8000"
          "--workers 1"
          "--threads 4"
          "--timeout 120"
          "--access-logfile -"
          "g7afd:app"
        ];
        EnvironmentFile = config.sops.secrets.easy-afd-env.path;

        # Graceful reload: gunicorn's master re-execs its workers on
        # SIGHUP, which re-imports the app and so picks up both new
        # Python and new Jinja templates (Jinja caches compiled
        # templates per process, so an rsync alone changes nothing).
        # Lets deploy.sh use `systemctl reload` and not drop requests.
        ExecReload = "${lib.getExe' pkgs.coreutils "kill"} -HUP $MAINPID";

        # "always", not "on-failure": a clean exit(0) is still an
        # outage. on-failure would leave the app down if gunicorn were
        # terminated by anything other than systemd itself.
        Restart = "always";
        RestartSec = "5s";
      };
  };

  systemd.services.easy-afd-refresh = {
    description = "Refresh Easy A/FD bulk aeronautical data";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    environment.PYTHONPATH = appDir;

    # A failed refresh pages, with the error, the night it happens
    # (notify-failure@ lives in gatus.nix with the rest of the alerting).
    # Before this the only signal was the absence of a success heartbeat,
    # and that took weeks to add up to an alert.
    onFailure = ["notify-failure@%n.service"];

    # ...but only after three tries. With Restart= set (below), systemd
    # retries a failed run and the unit does not enter "failed" — the
    # state onFailure reacts to — until this start limit refuses a fourth
    # attempt, about 45 minutes in. The FAA's servers answer 503 for
    # minutes at a time; a page should mean a person is needed.
    #
    # Unit-level for the reason given on easy-afd above. Side effect to
    # know about: once the limit is hit, a manual `systemctl start` is
    # refused too until `systemctl reset-failed easy-afd-refresh`.
    startLimitBurst = 3;
    startLimitIntervalSec = 2 * 60 * 60;

    serviceConfig =
      hardening
      // {
        Type = "oneshot";
        User = "easy-afd";
        Group = "easy-afd";
        StateDirectory = "easy-afd";
        WorkingDirectory = stateDir;
        ExecStart = refresh;
        Restart = "on-failure";
        RestartSec = "15min";
        # "+" = run as root: have the app pick up the fresh data (it
        # opens the stores and loads the pickles when a worker starts).
        # ExecStopPost rather than ExecStartPost because it also runs
        # when ExecStart failed: the sources are independent, so a run
        # that failed on one has usually still replaced the others.
        # Reload, not restart — gunicorn re-execs its workers without
        # dropping requests, which matters now that this is nightly.
        ExecStopPost = "+${lib.getExe' pkgs.systemd "systemctl"} try-reload-or-restart easy-afd.service";
        EnvironmentFile = config.sops.secrets.easy-afd-env.path;
      };
  };

  # Daily, within the hour after local midnight.
  #
  # The app decides which 28-day cycle is "current" by the date, so at
  # midnight on changeover day it starts describing the data it holds as
  # expired; refreshing then keeps that to about an hour. The new files
  # are already there — the FAA posts each cycle some three weeks ahead.
  # This was weekly, which left the data stale for up to seven days every
  # fourth week and made "is it current?" useless as an alert condition
  # (see easy-afd-data in gatus.nix). A run costs ~30 MB and ~3 minutes.
  systemd.timers.easy-afd-refresh = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };
}
