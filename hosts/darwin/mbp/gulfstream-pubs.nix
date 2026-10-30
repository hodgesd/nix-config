# Files Gulfstream AFMs and OMs dropped into iCloud's Pubs/Gulfstream/New Pubs:
# renames them from their own front matter, moves the superseded revision to
# Archive/, sends duplicates to to_delete/, and parks anything it can't
# identify in "New Pubs/Needs Review". Rules and naming are in
# gulfstream-pubs/file_new_pubs.py; outcomes show as banners (click reveals
# the file) and in ~/Library/Logs/gulfstream-pubs.log.
#
# mbp only: the folder syncs through iCloud, so a second Mac watching it
# would race this one for the same file.
{
  lib,
  pkgs,
  username,
  ...
}: let
  home = "/Users/${username}";
  root = "${home}/Library/Mobile Documents/com~apple~CloudDocs/Enterprise/Pubs/Gulfstream";
in {
  launchd.user.agents.gulfstream-pubs = {
    # nix-darwin sets PATH from this list exclusively; the script calls
    # /usr/bin/open and /usr/bin/osascript by absolute path.
    path = [pkgs.python3 pkgs.poppler-utils pkgs.terminal-notifier];
    serviceConfig = {
      # User agent, not daemon: iCloud Drive belongs to the login session.
      # launchd starts the job on any change in the folder, including the
      # script's own moves; those reruns find nothing and exit.
      WatchPaths = ["${root}/New Pubs"];
      StandardOutPath = "${home}/Library/Logs/gulfstream-pubs.log";
      StandardErrorPath = "${home}/Library/Logs/gulfstream-pubs.log";
    };
    script = ''
      exec python3 ${./gulfstream-pubs/file_new_pubs.py} ${lib.escapeShellArg root}
    '';
  };
}
