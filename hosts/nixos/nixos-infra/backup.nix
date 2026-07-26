# Nightly mirror of everything non-regenerable on this VM to the
# UNAS Pro 8 "backups" share (SMB, creds /etc/nas-backup.credentials,
# user nixos-backup scoped to that share). History/versioning comes
# from snapshots on the share, so this is a plain --delete mirror.
# Covered: the docker estate /srv/homelab (actual-budget ledger,
# uptime-kuma, ntfy, homepage, compose file) and a break-glass plaintext
# copy of the sops secrets (from /run/secrets — lets you recover even if
# every age key is lost). /etc/nixos is no longer mirrored: the config
# lives in the nix-config repo on GitHub. /var/lib/easy-afd is excluded —
# refresh scripts rebuild it and its pickles are pandas-coupled.
# Containers are paused around the homelab copy so SQLite files
# aren't torn mid-write (window is seconds for ~14 MB).
#
# NAS IP 192.168.1.142 also appears in storage.nix (Data share mount).
{
  config,
  pkgs,
  ...
}: let
  # Follow the daemon's docker package (docker_29) instead of pkgs.docker,
  # which is an older release marked insecure in 25.11.
  dockerPkg = config.virtualisation.docker.package;
  backup = pkgs.writeShellScript "homelab-backup" ''
    set -eu
    creds=${config.sops.secrets.nas-backup-credentials.path}
    if [ ! -f "$creds" ]; then
      echo "no $creds - skipping NAS backup" >&2
      exit 0
    fi
    compose="${dockerPkg}/bin/docker compose -f /srv/homelab/docker-compose.yml"
    mnt=$(${pkgs.coreutils}/bin/mktemp -d)
    ${pkgs.cifs-utils}/bin/mount.cifs //192.168.1.142/backups "$mnt" \
      -o credentials="$creds",vers=3.0,dir_mode=0700,file_mode=0600
    trap '$compose unpause >/dev/null 2>&1 || true; ${pkgs.util-linux}/bin/umount "$mnt" && rmdir "$mnt"' EXIT
    dest="$mnt/nixos-infra"
    mkdir -p "$dest/secrets"
    $compose pause
    # metube downloads live on the NAS itself (/mnt/data/Videos/MeTube),
    # so /srv/homelab holds only its small queue state — no excludes.
    ${pkgs.rsync}/bin/rsync -a --delete /srv/homelab/ "$dest/homelab/"
    $compose unpause
    for f in easy-afd-env cloudflare-acme-env nas-backup-credentials homelab-env; do
      ${pkgs.coreutils}/bin/install -m 600 "/run/secrets/$f" "$dest/secrets/"
    done
    ${pkgs.coreutils}/bin/date -u +%FT%TZ > "$dest/last-backup.txt"
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
