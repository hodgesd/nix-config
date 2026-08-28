# Nightly mirror of Uptime Kuma's data to the UNAS Pro 8 "backups" share —
# the macOS counterpart of hosts/nixos/nixos-infra/backup.nix, and the
# reason it exists: Kuma moved off the VM on 2026-08-08, so its data left
# /srv/homelab and stopped being covered by that job.
#
# Covered: ~/srv/uptime in full — uptime-kuma/ (monitors, history, push
# tokens) and ts-uptime/state (the tailnet node identity that keeps the URL
# and every push-monitor token stable). Losing the latter means re-registering
# the node, which breaks the token URLs the migration was built to preserve.
#
# History/versioning comes from NAS snapshots (daily 05:00, keep 64), so
# this is a plain --delete mirror, same as the VM's.
#
# NAS IP 192.168.1.142 also appears in hosts/nixos/nixos-infra/{backup,storage}.nix.
{
  config,
  pkgs,
  username,
  ...
}: let
  stateDir = "/Users/${username}/srv/uptime";
  nas = "192.168.1.142";
in {
  # Readable by the user, not just root: the agent below is a *user* agent
  # (it needs OrbStack's user-owned docker socket to pause containers), so
  # the sops default of root-only would leave it unable to read its own
  # credentials — and only at runtime, long after activation looked clean.
  # (The sops base config — defaultSopsFile, age key — lives in
  # default.nix, which grew it for the Hermes bridge tokens.)
  sops.secrets.nas-backup-credentials = {
    owner = username;
    mode = "0400";
  };

  launchd.user.agents.uptime-backup = {
    # rsync from nixpkgs deliberately: /usr/bin/rsync on macOS 26 is
    # openrsync (protocol 29), Apple's BSD reimplementation, whose
    # -a/--delete semantics are not guaranteed to match GNU rsync's.
    # docker_29 matches the compose module and the OrbStack server version.
    # nix-darwin sets PATH from this list *exclusively*, so anything not
    # here must be an absolute path (see mount_smbfs/umount below).
    path = [pkgs.rsync pkgs.docker_29 pkgs.docker-compose pkgs.coreutils pkgs.gnused];
    environment.DOCKER_HOST = "unix:///Users/${username}/.orbstack/run/docker.sock";
    serviceConfig = {
      # 04:00: after the VM's 03:30 (+30m jitter) so the two don't contend
      # for the share, and before the NAS's 05:00 snapshot so each night's
      # copy is actually captured in that day's snapshot.
      #
      # launchd has no equivalent of the VM timer's Persistent or
      # RandomizedDelaySec — a missed run is simply missed. The mini is
      # configured never to sleep (hosts/darwin/mini/default.nix), so in
      # practice the only way to miss one is being powered off.
      StartCalendarInterval = [
        {
          Hour = 4;
          Minute = 0;
        }
      ];
      RunAtLoad = false;
      StandardOutPath = "/Users/${username}/Library/Logs/uptime-backup.log";
      StandardErrorPath = "/Users/${username}/Library/Logs/uptime-backup.log";
    };
    script = ''
      set -eu

      creds=${config.sops.secrets.nas-backup-credentials.path}
      if [ ! -f "$creds" ]; then
        echo "no $creds - skipping NAS backup" >&2
        exit 0
      fi
      user=$(sed -n 's/^username=//p' "$creds")
      pass=$(sed -n 's/^password=//p' "$creds")

      # `docker-compose` standalone, not `docker compose`: the plugin is
      # resolved from docker's own cli-plugins dirs, not PATH, and this
      # agent's PATH is the nix store only. Same choice as the compose
      # module, which is proven on this host.
      compose="docker-compose --project-directory ${stateDir} -f ${stateDir}/docker-compose.yml"
      mnt=$(mktemp -d)

      # Unpause before unmounting: if rsync dies, containers must not be
      # left frozen — a paused Kuma is a blind Kuma, which is worse than a
      # missed backup.
      trap '$compose unpause >/dev/null 2>&1 || true; /sbin/umount "$mnt" >/dev/null 2>&1 || true; rmdir "$mnt" 2>/dev/null || true' EXIT

      # macOS has no `mount.cifs -o credentials=`. The password goes in the
      # URL because nothing else works here: mount_smbfs on macOS 26 ignores
      # passwords in ~/.nsmbrc (all section forms tested), `smbutil crypt`
      # has been removed, and getpass() reads /dev/tty so stdin is not an
      # option either. It reads the argv only for the fraction of a second
      # the mount takes, and the sole accounts on this host are this user —
      # who owns $creds anyway — and root, who can read /run/secrets
      # directly. Revisit if this box ever gains other users.
      /sbin/mount_smbfs "//$user:$pass@${nas}/backups" "$mnt"

      dest="$mnt/mini"
      # BSD mkdir, not coreutils'. GNU `mkdir -p` hangs indefinitely on an
      # smbfs mount here — no error, it just blocks, which under launchd
      # means a job wedged forever holding the mount. /bin/mkdir returns
      # instantly. (GNU rsync is fine over smbfs; this is mkdir-specific.)
      /bin/mkdir -p "$dest"

      # Kuma's SQLite is live; pause narrows the window to the seconds the
      # ~5 MB copy takes, exactly as the VM's job does for the same reason.
      $compose pause
      rsync -a --delete ${stateDir}/ "$dest/uptime/"
      $compose unpause

      date -u +%FT%TZ > "$dest/last-backup.txt"
    '';
  };
}
