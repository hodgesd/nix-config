# Nightly mirror of everything non-regenerable on this VM to the
# UNAS Pro 8 "backups" share (SMB, creds /etc/nas-backup.credentials,
# user nixos-backup scoped to that share). History/versioning comes
# from snapshots on the share, so this is a plain --delete mirror.
# Covered: the docker estate /srv/homelab (actual-budget ledger,
# ntfy, homepage, compose file), hermes-agent state
# /var/lib/hermes/.hermes (sessions + config; small, no quiesce needed), and a
# break-glass plaintext copy of the sops secrets (from /run/secrets — lets
# you recover even if every age key is lost). /etc/nixos is no longer
# mirrored: the config lives in the nix-config repo on GitHub.
# /var/lib/easy-afd is excluded — refresh scripts rebuild it and its
# pickles are pandas-coupled.
# Containers are paused around the homelab copy so SQLite files
# aren't torn mid-write (window is seconds for ~14 MB).
#
# Alerting: this unit failed silently every night 2026-09-15 → 09-25
# (exit 127, nothing watched it). It now reports to a healthchecks.io check
# (HC_BACKUP_PING_URL in the healthchecks-env secret, next to the VM
# dead-man): a success ping at the very end of a run, a /fail ping from the
# EXIT trap otherwise. Configure the check as period 1 day / grace 26 h, so
# a broken run alerts the same night and a run that never starts (timer
# gone, creds missing, VM asleep) alerts once a night is missed — through
# the same off-site channel as the VM heartbeat, independent of ntfy/Gatus.
#
# NAS IP 192.168.1.142 also appears in storage.nix (Data share mount).
{
  config,
  lib,
  pkgs,
  ...
}: let
  # Follow the daemon's docker package (docker_29) instead of pkgs.docker,
  # which is an older release marked insecure in 25.11. (hermes.nix solves
  # the same mismatch the other way, with a host-global overlay rebinding
  # pkgs.docker → docker_29 for the upstream module's sake — so on this
  # host the two expressions currently agree.)
  dockerPkg = config.virtualisation.docker.package;
  backup = pkgs.writeShellScript "homelab-backup" ''
    set -eu
    # healthchecks.io ping; "$1" is "" (success) or "/fail". An empty or
    # missing HC_BACKUP_PING_URL is a no-op (the check then alerts on its
    # grace timer — still a signal). A ping failure never fails the backup.
    hc() {
      [ -n "''${HC_BACKUP_PING_URL:-}" ] || return 0
      ${lib.getExe pkgs.curl} -fsS -m 10 --retry 3 --retry-delay 5 \
        "$HC_BACKUP_PING_URL$1" >/dev/null \
        || echo "healthchecks.io ping$1 failed (backup status unaffected)" >&2
    }
    creds=${config.sops.secrets.nas-backup-credentials.path}
    if [ ! -f "$creds" ]; then
      # Deliberately no success ping: a skipped backup is a missed backup,
      # and the check's grace period should say so.
      echo "no $creds - skipping NAS backup" >&2
      exit 0
    fi
    compose="${dockerPkg}/bin/docker compose -f /srv/homelab/docker-compose.yml"
    mnt=$(${pkgs.coreutils}/bin/mktemp -d)
    # Installed before the mount so that a failure anywhere (including the
    # 2026-09 case, where mount.cifs itself was missing) reaches /fail.
    cleanup() {
      rc=$?
      $compose unpause >/dev/null 2>&1 || true
      if ${pkgs.util-linux}/bin/mountpoint -q "$mnt"; then
        ${pkgs.util-linux}/bin/umount "$mnt" || rc=1
      fi
      rmdir "$mnt" 2>/dev/null || true
      [ "$rc" -eq 0 ] || hc /fail
      exit "$rc"
    }
    trap cleanup EXIT
    # getExe' picks the `bin` output. Since nixpkgs 26.05 cifs-utils is split
    # into outputs and the default one holds only lib/, so the plain
    # ''${pkgs.cifs-utils} interpolation used before pointed at a mount.cifs
    # that did not exist: the backup failed every night (exit 127) from
    # 2026-09-15 to 2026-09-25 and nothing alerted.
    ${lib.getExe' pkgs.cifs-utils "mount.cifs"} //192.168.1.142/backups "$mnt" \
      -o credentials="$creds",vers=3.0,dir_mode=0700,file_mode=0600
    dest="$mnt/nixos-infra"
    mkdir -p "$dest/secrets"
    $compose pause
    # metube downloads live on the NAS itself (/mnt/data/Videos/MeTube),
    # so /srv/homelab holds only its small queue state — no excludes.
    ${pkgs.rsync}/bin/rsync -a --delete /srv/homelab/ "$dest/homelab/"
    $compose unpause
    # Hermes: only .hermes (sessions, config, cron, media cache — ~20M) is
    # worth keeping. NOT the parent /var/lib/hermes: home/ is a ~170M
    # regenerable uv Python toolchain whose thousands of symlinks SMB
    # cannot store (rsync dies on I/O errors, and set -eu then skips the
    # secrets mirror below). Not part of the compose estate, so the pause
    # window doesn't apply. -rlt instead of -a: .hermes/skills contains
    # read-only dirs, and preserving that mode sets the DOS read-only
    # attribute on the share, which blocks every later --delete update
    # (the mount's dir_mode/file_mode already yield sane modes).
    ${pkgs.rsync}/bin/rsync -rlt --delete /var/lib/hermes/.hermes/ "$dest/hermes/"
    for f in easy-afd-env cloudflare-acme-env nas-backup-credentials homelab-env hermes-env; do
      ${pkgs.coreutils}/bin/install -m 600 "/run/secrets/$f" "$dest/secrets/"
    done
    # hodgesd-password is neededForUsers, so it lives outside /run/secrets.
    ${pkgs.coreutils}/bin/install -m 600 ${config.sops.secrets.hodgesd-password.path} "$dest/secrets/"
    ${pkgs.coreutils}/bin/date -u +%FT%TZ > "$dest/last-backup.txt"
    # Last line on purpose: anything after this would fail unreported.
    hc ""
  '';
in {
  # Runs as root: mounting and reading the secrets need privileges.
  systemd.services.homelab-backup = {
    description = "Nightly homelab backup to UNAS Pro 8";
    after = ["network-online.target" "docker.service"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = backup;
      # HC_BACKUP_PING_URL. The ping URL is a credential (whoever holds it
      # can keep the check green), so it lives in the same sops dotenv as
      # the VM heartbeat rather than in this file. The secret is declared
      # in healthchecks.nix; re-read on every run, so no restartUnits.
      EnvironmentFile = config.sops.secrets.healthchecks-env.path;
    };
  };

  systemd.timers.homelab-backup = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "*-*-* 03:30";
      Persistent = true;
      RandomizedDelaySec = "30m";
    };
  };
}
