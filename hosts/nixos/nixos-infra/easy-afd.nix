# Easy A/FD (github.com/hodgesd/gvii_afd-backup) as a systemd service:
# the app itself, the weekly data refresh, and the Kuma healthcheck.
# The nginx/ACME front is proxy.nix; NAS backup is backup.nix.
#
# KNOWN GAP (out of scope): source lives in /srv/easy-afd, rsynced from
# the dev Mac over Tailscale (the repo is private so it is not fetched
# at build time). A from-scratch rebuild has a broken easy-afd.service
# until that rsync runs — see docs/NIXOS-INFRA.md.
#
# Mutable data lives in /var/lib/easy-afd: the app opens
# best_apprs.pickle, dtpp_charts.pickle and data/*.sqlite relative to
# its working directory, and writes *_cache_v2.json weather caches there.
#
# IMPORTANT: never copy data/ from another machine — data/alternates.pickle
# is pandas-version-coupled (dev Mac runs pandas 3.x, nixpkgs ships 2.x).
# The easy-afd-refresh service rebuilds all of data/ locally instead.
#
# Secrets (Autorouter credentials) live in /etc/easy-afd.env, root-only;
# systemd reads it before dropping privileges. (Moves to sops-nix in a
# later phase.)
{
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

  # Rebuild the bulk aeronautical data (NASR 28-day cycle, OurAirports,
  # openAIP PCN overlay) into ${stateDir}/data.
  refresh = pkgs.writeShellScript "easy-afd-refresh" ''
    set -eu
    cd ${stateDir}
    ${pyEnv}/bin/python ${appDir}/scripts/refresh_faa_data.py --nasr --data-dir ${stateDir}/data
    ${pyEnv}/bin/python ${appDir}/scripts/refresh_ourairports_data.py --data-dir ${stateDir}/data
    # Non-fatal: needs OPENAIP_API_KEY (in /etc/easy-afd.env) since
    # openAIP's bulk exports went requester-pays (2026-07-22); on any
    # failure the PCN overlay just goes stale and the app degrades
    # gracefully without it.
    ${pyEnv}/bin/python ${appDir}/scripts/refresh_openaip_data.py --data-dir ${stateDir}/data \
      || echo "openaip refresh failed (non-fatal)" >&2
    # Success heartbeat for the Uptime Kuma push monitor. Set
    # KUMA_REFRESH_PUSH_URL in /etc/easy-afd.env; skipped when unset.
    if [ -n "''${KUMA_REFRESH_PUSH_URL:-}" ]; then
      ${pkgs.curl}/bin/curl -fsS -m 10 --retry 3 "''${KUMA_REFRESH_PUSH_URL}" >/dev/null \
        || echo "kuma heartbeat push failed" >&2
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
        EnvironmentFile = "/etc/easy-afd.env";
        Restart = "on-failure";
      };
  };

  systemd.services.easy-afd-refresh = {
    description = "Refresh Easy A/FD bulk aeronautical data";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    environment.PYTHONPATH = appDir;

    serviceConfig =
      hardening
      // {
        Type = "oneshot";
        User = "easy-afd";
        Group = "easy-afd";
        StateDirectory = "easy-afd";
        WorkingDirectory = stateDir;
        ExecStart = refresh;
        # "+" = run as root: pick up the fresh data (the app loads the
        # sqlite stores and alternates pickle at import time).
        ExecStartPost = "+${lib.getExe' pkgs.systemd "systemctl"} try-restart easy-afd.service";
        EnvironmentFile = "/etc/easy-afd.env";
      };
  };

  # NASR data runs a 28-day cycle; weekly keeps it comfortably fresh.
  systemd.timers.easy-afd-refresh = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };

  # Self-check dead-man's switch: Kuma's container can't route to the
  # tailnet, so instead of polling us it expects a heartbeat. Checking
  # via the public name exercises DNS, nginx, the LE cert, and the app
  # in one shot; a stopped heartbeat (3 min window on the Kuma side)
  # means one of those is down.
  systemd.services.easy-afd-healthcheck = {
    description = "Heartbeat Easy A/FD health to Uptime Kuma";
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = "/etc/easy-afd.env";
    };
    script = ''
      ${pkgs.curl}/bin/curl -fsS -m 10 https://afd.hdgs.me/healthz >/dev/null
      if [ -n "''${KUMA_AFD_PUSH_URL:-}" ]; then
        ${pkgs.curl}/bin/curl -fsS -m 10 "''${KUMA_AFD_PUSH_URL}" >/dev/null
      fi
    '';
  };
  systemd.timers.easy-afd-healthcheck = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnBootSec = "2m";
      OnUnitActiveSec = "60s";
    };
  };
}
