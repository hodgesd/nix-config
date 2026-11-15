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
#   - The UNAS share's credential (user bill-filer). It is a Keychain entry,
#     interactive by nature; putting a NAS password through sops would move a
#     household credential into this public repo to save a one-time dialog.
#     Keeping the share mounted IS declared (billfiler-mount, below, on every
#     Mac); it reads that Keychain entry, so each Mac needs it saved once.
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
  # The UNAS. Same IP as hosts/darwin/mbp/backup.nix and nixos-infra's
  # backup.nix and storage.nix.
  nas = "192.168.1.142";
  archive = "/Volumes/Data/Documents";
  mirror = "${home}/Library/Mobile Documents/com~apple~CloudDocs/Statements (read-only copy)";
  overwritten = "${home}/Library/Application Support/billfiler/mirror-overwritten";
  mirrorLog = "${home}/Library/Logs/billfiler-mirror.log";
  # ntfy is tailnet-only with no auth, so the topic name is not a secret.
  alerts = "https://ntfy.jaguar-duckbill.ts.net/hermes-alerts";
in {
  environment.systemPackages = [billfiler];

  # Menu bar on every Mac, reading the index off the share.
  # Sourced from the billfiler input rather than the swiftbar_plugins repo so
  # the plugin and the CLI it shells out to move as one.
  home-manager.users.${config.majordouble.user}.programs.swiftbar.plugins = {
    "bills.4h.py".source = "${billfiler}/share/billfiler/bills.4h.py";
  };

  # Keeps the share mounted, on every Mac: the menu bar on each reads the
  # index off it, and the mini's mover and mirror need it to do anything.
  #
  # It was a run-once-at-login job, and on 2026-11-15 at 00:04 the NAS dropped
  # both Macs' SMB sessions (mini kernel log: "iod 7 is dead, give up"). macOS
  # unmounted the share, nothing mounted it again, and the mover failed every
  # run for eight hours with no alert -- it kept logging, so the mover check
  # below saw a healthy log.
  #
  # Every 5 minutes, then:
  #   mounted and readable  -> nothing
  #   mounted, unreadable   -> log; on the mini, alert (a mount that is listed
  #                            but dead, which `mount` alone cannot see)
  #   not mounted           -> mount it, if the NAS answers
  # One alert when it goes down and one when it is back, mini only: a laptop
  # away from home is not an outage.
  #
  # An inline module only so this agent can sit outside the mini-only mkIf
  # below while sharing this file's let-bindings.
  #
  # Mount it now:
  #   launchctl kickstart gui/$(id -u)/org.nixos.billfiler-mount
  imports = [
    {
      launchd.user.agents.billfiler-mount = {
        serviceConfig = {
          RunAtLoad = true;
          StartInterval = 300;
          ProcessType = "Background";
          StandardOutPath = logPath;
          StandardErrorPath = logPath;
        };
        command = toString (pkgs.writeScript "billfiler-mount" ''
          #!/bin/bash
          set -u
          PATH=/usr/bin:/bin:/sbin
          # The mini is always home, so a share it cannot reach is an outage.
          # A laptop may just be away: it logs, never alerts.
          alert=${lib.boolToString (machine.hostname == "mini")}
          flag="${home}/Library/Application Support/billfiler/share-down"
          # A push needs the tailnet; the flag changes only after one goes
          # through, so a failed push is retried on the next run.
          notify() {
            curl -fsS -m 10 -H "Title: $1" -H "Priority: $2" -H "Tags: $3" \
              -d "$4" ${alerts} >/dev/null
          }
          down() {
            echo "$(date '+%F %T') $1"
            if [ "$alert" = true ] && [ ! -e "$flag" ]; then
              notify "Bill Filer: UNAS share down" high warning \
                "$1. Nothing files until it is back; this job retries every 5 minutes." \
                && mkdir -p "$(dirname "$flag")" && touch "$flag"
            fi
            exit 1
          }
          up() {
            if [ -e "$flag" ]; then
              notify "Bill Filer: UNAS share back" default white_check_mark \
                "The share is mounted again." && rm -f "$flag"
            fi
            exit 0
          }
          # Only /Volumes/Data counts: a stale directory left there makes
          # macOS mount at /Volumes/Data-1, which the mover and mirror ignore,
          # so that case reports as down instead of passing quietly.
          mounted() { mount | grep -q ' on /Volumes/Data (smbfs'; }

          if mounted; then
            # Same check the mirror trusts before it runs.
            [ -d "${archive}/Bills" ] && up
            down "/Volumes/Data is mounted but ${archive}/Bills is not readable"
          fi

          # WHY probe before mounting: away from home the NAS is unreachable
          # (LAN-only, not on the tailnet), and this keeps a laptop from
          # logging a failure every 5 minutes. Caveat, same as the mbp backup:
          # a foreign network that also has an SMB server at this address
          # would be offered the bill-filer login. SMB sends a challenge
          # response, not the password, but a hostile server could try to
          # crack it offline. Accepted for a LAN-only household share.
          if ! nc -z -G 3 ${nas} 445 >/dev/null 2>&1; then
            [ "$alert" = true ] && down "the NAS at ${nas} is not answering on SMB"
            exit 0
          fi

          osascript -e 'mount volume "smb://bill-filer@${nas}/Data"' >/dev/null \
            && mounted && up
          down "could not mount //bill-filer@${nas}/Data on /Volumes/Data"
        '');
      };
    }
  ];

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

    # Alerts when the mover stops running. Its macOS grants for the share and
    # the iCloud inbox belong to the Nix bash in its Python wrapper's shebang
    # (the mini's TCC database, 2026-11-14), so a nixpkgs bash bump re-prompts
    # on the mini's screen, and the waiting run hangs with nothing in the log
    # and blocks the next ones, like the mirror below. The mover writes its log
    # every run (every 10 minutes, offline or not), so a log untouched for 30
    # minutes means it is stuck. Fix: Screen Share to the mini and click Allow.
    #
    # A separate job rather than a watchdog wrapped around the mover: starting
    # the mover from a script would move its grant from that bash onto Python
    # (as apple-mcp's did), which re-prompts now and on every Python update.
    # One push when it goes stale and one when it recovers, same topic as the
    # mirror.
    billfiler-mover-check = {
      serviceConfig = {
        StartInterval = 900;
        ProcessType = "Background";
        # NOT logPath: writing there would refresh the age it checks.
        StandardOutPath = "${home}/Library/Logs/billfiler-mover-check.log";
        StandardErrorPath = "${home}/Library/Logs/billfiler-mover-check.log";
      };
      command = toString (pkgs.writeScript "billfiler-mover-check" ''
        #!/bin/bash
        set -u
        PATH=/usr/bin:/bin
        flag="${home}/Library/Application Support/billfiler/mover-stuck"
        # The flag changes only after a push goes through, so a failed one
        # is retried on the next check.
        notify() {
          curl -fsS -m 10 -H "Title: $1" -H "Priority: $2" -H "Tags: $3" \
            -d "$4" ${alerts} >/dev/null
        }
        if [ -n "$(find "${logPath}" -mmin +30)" ]; then
          if [ ! -e "$flag" ]; then
            notify "Bill Filer: mover stuck" high warning \
              "No mover run logged for 30 minutes. Most likely a hidden macOS prompt on the mini after a bash update: Screen Share in and click Allow." \
              && mkdir -p "$(dirname "$flag")" && touch "$flag"
          fi
        elif [ -e "$flag" ]; then
          notify "Bill Filer: mover running again" default white_check_mark \
            "The mover is logging its runs again." \
            && rm -f "$flag"
        fi
      '');
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
    # macOS privacy (TCC): the grants for the share (Network Volumes) and
    # for iCloud Drive belong to rsync's Nix store path, not to the shell
    # (the mini's TCC log and database, 2026-11-14). So every nixpkgs rsync
    # bump re-prompts on the mini's screen, and until someone clicks Allow
    # the run hangs in open() with nothing in the log, and launchd starts no
    # new run while it waits. The watchdog in the script pushes an alert
    # when a run passes 15 minutes. Fix: Screen Share to the mini and click
    # Allow; the waiting run then finishes by itself. (If Don't Allow was
    # clicked instead, the log says "Operation not permitted": turn rsync
    # back on under Privacy & Security, then kickstart below.)
    #
    # The shebang is Apple's /bin/bash, and that does NOT make the grant
    # last. What it does: with a platform shell as the launched process, TCC
    # charges each access to the tool making it, so the grant sits on rsync
    # alone. Under a Nix bash it would land on that bash instead, as the
    # mover's does through its Python wrapper. Kept so as not to re-prompt.
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

        # Watchdog for the hang described above (or a share that hangs
        # mid-run). One push per stuck run, to the topic the Hermes sentinel
        # uses for the mini's other TCC failure (calendar-access). It does not
        # kill rsync: an Allow at the screen lets the waiting run finish.
        (
          sleep 900
          curl -fsS -m 10 -H "Title: Bill Filer: mirror stuck" \
            -H "Priority: high" -H "Tags: warning" \
            -d "The iCloud copy has run 15 minutes. Most likely a hidden macOS prompt for rsync on the mini: Screen Share in and click Allow. Log: ~/Library/Logs/billfiler-mirror.log" \
            ${alerts} >/dev/null || true
        ) &
        watchdog=$!

        # --max-delete caps a run at 25 deletions and fails it (exit 25, in
        # the log) past that; ordinary filing never deletes that many at
        # once. Every deleted file is also kept in `overwritten`.
        # From Documents/ with only Bills/ and Income/ let in, and
        # --delete-excluded, so a stray file anywhere in the copy (its root
        # included) is removed too, never just inside the two folders.
        rc=0
        out=$(rsync -rti --delete --delete-excluded --max-delete=25 \
          --exclude _meta/ --exclude _Unsorted/ \
          --exclude '.billfiler-*' --exclude .DS_Store \
          --include /Bills/ --include /Income/ --exclude '/*' \
          --backup --backup-dir="${overwritten}/$(date +%F_%H%M%S)" \
          "${archive}/" "${mirror}/") || rc=$?
        kill "$watchdog" 2>/dev/null || true
        # Log only runs that changed something, including a failed run's
        # partial changes (the 25 deletions a capped run did make).
        if [ -n "$out" ]; then
          echo "$(date '+%F %T') mirrored"
          echo "$out"
        fi
        exit "$rc"
      '');
    };
  };
}
