# hosts/common/darwin/billfiler/default.nix
# Bill Filer: a statement PDF saved to an iCloud inbox gets filed to the UNAS
# under its vendor with a clean name, its figures land in a SQLite index, and
# the menu bar shows the month against last month, last year, and that
# vendor's own trailing average. Upstream: github.com/hodgesd/billfiler.
#
# Every Mac gets the CLI and the menu bar plugin; ONLY the mini runs the
# mover. That split is the mkIf below rather than a flag to remember, because
# it is not a preference: the mover's lock lives under
# ~/Library/Application Support, so it does not protect across machines. Two
# Macs watching one iCloud inbox would race for the same PDF.
#
# Deliberately NOT declarative:
#   - The SMB mount of the UNAS share. Its credential is a Keychain entry,
#     interactive by nature; putting a NAS password through sops would move a
#     household credential into this public repo to save a one-time dialog.
#   - `billfiler init`, which creates the archive. That writes data, not
#     config, and it needs the share already mounted.
#   - The registry (Bills/_meta/vendors.yaml) and the templates beside it.
#     Those live on the share on purpose so both Macs read one copy; managing
#     them here would give each Mac its own and leave the shared copy
#     ambiguous.
{
  config,
  inputs,
  lib,
  machine,
  pkgs,
  username,
  ...
}: let
  billfiler = pkgs.callPackage ./package.nix {src = inputs.billfiler;};

  home = "/Users/${username}";
  inbox = "${home}/Library/Mobile Documents/com~apple~CloudDocs/Bills Inbox";
  logPath = "${home}/Library/Logs/billfiler.log";

  # The mirror (below): the archive on the share, copied one way into iCloud
  # Drive so the statements can be read offline on the iPad.
  archive = "/Volumes/Data/Documents";
  mirror = "${home}/Library/Mobile Documents/com~apple~CloudDocs/Statements (read-only copy)";
  overwritten = "${home}/Library/Application Support/billfiler/mirror-overwritten";
  mirrorLog = "${home}/Library/Logs/billfiler-mirror.log";
in {
  environment.systemPackages = [billfiler];

  # Menu bar on every Mac, reading the index off the share.
  # Sourced from the billfiler input rather than the swiftbar_plugins repo so
  # the plugin and the CLI it shells out to move as one.
  home-manager.users.${config.majordouble.user}.programs.swiftbar.plugins = {
    "bills.4h.py".source = "${billfiler}/share/billfiler/bills.4h.py";
  };

  # The mover, on the mini only -- see the header for why that is structural.
  #
  # Keyed on the hostname, NOT on `primaryUse == "server"`: that role has held
  # more than one Mac at a time (studio did, until #121 retired it), and the
  # role gate duly installed a second mover on a box with no Apple ID, no inbox
  # and no share -- the exact double-filing race the header argues against.
  # Retiring studio did not make the gate safe, it just emptied the trap: "the
  # Mac holding the iCloud inbox and the UNAS mount" is not a role that exists,
  # it is this one machine, and the next server-role Mac would spring it again.
  #
  # These are USER agents, with the same consequence as this host's Hermes
  # bridges: the inbox lives in the user's iCloud session and the UNAS share
  # is mounted in the user's GUI session, so nothing files until someone is
  # logged in. FileVault with no auto-login means an unexpected power cut
  # leaves the mover down at the unlock screen. Nothing is lost -- the PDFs
  # sit in the inbox and the next run takes them.
  launchd.user.agents = lib.mkIf (machine.hostname == "mini") {
    billfiler = {
      serviceConfig = {
        ProgramArguments = ["${billfiler}/bin/billfiler" "run"];

        # A PDF is filed within seconds of iCloud landing it in the inbox.
        WatchPaths = [inbox];

        # Backstop for what the watch cannot see: an iCloud download that
        # completes later, a reboot, or the share offline at the time. A run
        # with an empty inbox is a no-op, and a run with the share unmounted
        # leaves the PDFs alone and says so in the log.
        StartInterval = 600;

        RunAtLoad = true;

        # Do not spin if a bad registry makes the run fail instantly.
        ThrottleInterval = 30;

        # Background, not Interactive: this is a short batch job, so App Nap
        # throttling it is harmless. (Contrast the bridges in
        # hosts/darwin/mini/default.nix, where it stalls an SSE loop.)
        ProcessType = "Background";

        StandardOutPath = logPath;
        StandardErrorPath = logPath;
      };
    };

    billfiler-weekly = {
      serviceConfig = {
        ProgramArguments = ["${billfiler}/bin/billfiler" "weekly"];

        # Sundays 03:30: walk the archive to repair the index, then snapshot
        # it. Weekday 0 is Sunday to launchd.
        StartCalendarInterval = [
          {
            Weekday = 0;
            Hour = 3;
            Minute = 30;
          }
        ];

        ProcessType = "Background";
        StandardOutPath = logPath;
        StandardErrorPath = logPath;
      };
    };

    # Hourly one-way copy of Bills/ and Income/ to iCloud Drive, for reading
    # statements away from home (the UNAS is LAN-only). The share stays the
    # archive. iCloud cannot make a folder read-only, so the folder name says
    # it, and anything changed or added there is reverted on the next run.
    # Whatever a run overwrites or deletes in the copy is moved to
    # `overwritten` first, so an edit made on the iPad is not lost.
    #
    # _meta (index, registry, templates) and _Unsorted (unidentified PDFs that
    # get renamed once a template exists) stay on the share only.
    # .billfiler-* is the mover's in-flight temp file.
    #
    # Shebang is Apple's /bin/bash, as for apple-mcp in
    # hosts/darwin/mini/default.nix: if macOS asks for network-volume or
    # iCloud access, the grant is charged to the interpreter, and Nix bash
    # would lose it on the next bash bump. An "Operation not permitted" in
    # the log means a prompt is waiting on the mini's screen.
    #
    # Force a run now, on mini:
    #   launchctl kickstart -k gui/$(id -u)/org.nixos.billfiler-mirror
    billfiler-mirror = {
      serviceConfig = {
        StartInterval = 3600;
        RunAtLoad = true;
        ProcessType = "Background";
        StandardOutPath = mirrorLog;
        StandardErrorPath = mirrorLog;
      };
      # Not `script =`: nix-darwin would give it a Nix bash shebang.
      command = toString (pkgs.writeScript "billfiler-mirror" ''
        #!/bin/bash
        set -eu
        # GNU rsync deliberately: /usr/bin/rsync is openrsync (see
        # hosts/darwin/mbp/backup.nix).
        PATH=${pkgs.rsync}/bin:/usr/bin:/bin:/sbin

        # WHY this guard: with --delete, an unmounted share (or a stale,
        # empty /Volumes/Data left behind) would look like an empty archive
        # and wipe the copy. Only a live SMB mount counts.
        mount | grep -q ' on /Volumes/Data (smbfs' || exit 0
        [ -d "${archive}/Bills" ] && [ -d "${archive}/Income" ] || exit 0

        mkdir -p "${mirror}"
        # --max-delete caps a run at 25 deletions and fails it (exit 25, in
        # the log) past that; ordinary filing never deletes that many at
        # once. Every deleted file is also kept in `overwritten`.
        # From Documents/ with only Bills/ and Income/ let in, and
        # --delete-excluded, so a stray file anywhere in the copy (its root
        # included) is removed too, never just inside the two folders.
        out=$(rsync -rti --delete --delete-excluded --max-delete=25 \
          --exclude _meta/ --exclude _Unsorted/ \
          --exclude '.billfiler-*' --exclude .DS_Store \
          --include /Bills/ --include /Income/ --exclude '/*' \
          --backup --backup-dir="${overwritten}/$(date +%F_%H%M%S)" \
          "${archive}/" "${mirror}/")
        # Log only runs that changed something.
        if [ -n "$out" ]; then
          echo "$(date '+%F %T') mirrored"
          echo "$out"
        fi
      '');
    };
  };
}
