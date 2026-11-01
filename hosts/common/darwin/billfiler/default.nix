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
in {
  environment.systemPackages = [billfiler];

  # Menu bar on every Mac, reading the index off the share over the tailnet.
  # Sourced from the billfiler input rather than the swiftbar_plugins repo so
  # the plugin and the CLI it shells out to move as one.
  home-manager.users.${config.majordouble.user}.programs.swiftbar.plugins = {
    "bills.4h.py".source = "${billfiler}/share/billfiler/bills.4h.py";
  };

  # The mover, on the mini only -- see the header for why that is structural.
  #
  # These are USER agents, with the same consequence as this host's Hermes
  # bridges: the inbox lives in the user's iCloud session and the UNAS share
  # is mounted in the user's GUI session, so nothing files until someone is
  # logged in. FileVault with no auto-login means an unexpected power cut
  # leaves the mover down at the unlock screen. Nothing is lost -- the PDFs
  # sit in the inbox and the next run takes them.
  launchd.user.agents = lib.mkIf (machine.primaryUse == "server") {
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
  };
}
