# Daily mirror of the mbp's un-versioned personal files to the UNAS Pro 8
# "backups" share, under backups/mbp/. Modeled on the mini's former
# uptime-backup job (deleted in af781b2 — see git history for its notes),
# which solved the macOS SMB quirks this reuses: password in the mount URL,
# BSD /bin/mkdir, GNU rsync from nixpkgs.
#
# Covered (small, not in git, not nix-managed):
#   ~/.config/swiftbar-plugins/  plugin configs + home_comps_uv.notes.md
#   ~/Documents/Maps/            subdivision map + its rebuild sources
#                                (Documents syncs to iCloud, but iCloud is
#                                sync, not backup)
#
# A laptop isn't home and awake at a fixed hour, and the NAS is LAN-only
# (not on the tailnet, no subnet route for 192.168.1.0/24). So the agent
# wakes hourly and does nothing unless (a) the NAS answers on SMB, i.e. we
# are home, and (b) the last success is older than minAgeHours. In practice:
# one run a day, the first hour the laptop is home.
#
# History/versioning comes from NAS snapshots (daily 05:00, keep 64), so this
# is a plain --delete mirror. No healthchecks.io ping (yet): irregular
# laptop schedules would need a multi-day grace; `last-backup.txt` on the
# share and ~/Library/Logs/mbp-backup.log show the last run.
#
# NAS IP 192.168.1.142 also appears in hosts/nixos/nixos-infra/{backup,storage}.nix.
{
  config,
  lib,
  pkgs,
  username,
  ...
}: let
  home = "/Users/${username}";
  nas = "192.168.1.142";
  minAgeHours = 20;
  # destination dir under backups/mbp/ -> source, relative to $HOME
  sources = {
    swiftbar-plugins = ".config/swiftbar-plugins";
    maps = "Documents/Maps";
  };
  stateDir = "${home}/.local/state/mbp-backup";
  copies = lib.concatStringsSep "\n" (lib.mapAttrsToList (dest: src: ''
      if [ -d ${lib.escapeShellArg "${home}/${src}"} ]; then
        # -rt, not -a: SMB can't store symlinks or POSIX modes (the mount's
        # defaults give sane ones); .DS_Store is noise.
        rsync -rt --delete --exclude .DS_Store \
          ${lib.escapeShellArg "${home}/${src}/"} "$dest/${dest}/"
      else
        echo "missing ${src} - skipped" >&2
      fi
    '')
    sources);
in {
  launchd.user.agents.mbp-backup = {
    # rsync from nixpkgs deliberately: /usr/bin/rsync on macOS 26 is
    # openrsync, whose -a/--delete semantics aren't guaranteed to match GNU
    # rsync's. nix-darwin sets PATH from this list *exclusively*, so system
    # tools below are absolute paths.
    path = [pkgs.rsync pkgs.coreutils pkgs.gnused];
    serviceConfig = {
      StartInterval = 3600;
      RunAtLoad = true;
      StandardOutPath = "${home}/Library/Logs/mbp-backup.log";
      StandardErrorPath = "${home}/Library/Logs/mbp-backup.log";
    };
    script = ''
      set -eu
      mkdir -p ${stateDir}
      stamp=${stateDir}/last-success

      # Quiet exits (no log line) for the common hourly no-op cases.
      if [ -f "$stamp" ]; then
        age=$(( $(date +%s) - $(cat "$stamp") ))
        [ "$age" -ge $(( ${toString minAgeHours} * 3600 )) ] || exit 0
      fi
      /usr/bin/nc -z -G 3 ${nas} 445 >/dev/null 2>&1 || exit 0

      echo "$(date '+%F %T') starting"
      creds=${config.sops.secrets.nas-backup-credentials.path}
      if [ ! -f "$creds" ]; then
        echo "no $creds - skipping NAS backup" >&2
        exit 0
      fi
      user=$(sed -n 's/^username=//p' "$creds")
      pass=$(sed -n 's/^password=//p' "$creds")

      mnt=$(mktemp -d)
      trap '/sbin/umount "$mnt" >/dev/null 2>&1 || true; rmdir "$mnt" 2>/dev/null || true' EXIT

      # macOS mount_smbfs ignores ~/.nsmbrc passwords and reads interactive
      # input from /dev/tty, so the password goes in the URL (visible in argv
      # only for the moment the mount takes; this is a single-user laptop).
      /sbin/mount_smbfs "//$user:$pass@${nas}/backups" "$mnt"

      dest="$mnt/mbp"
      # BSD mkdir: GNU `mkdir -p` hangs indefinitely on smbfs here.
      /bin/mkdir -p "$dest"
      ${copies}

      date -u +%FT%TZ > "$dest/last-backup.txt"
      date +%s > "$stamp"
      echo "$(date '+%F %T') done"
    '';
  };
}
