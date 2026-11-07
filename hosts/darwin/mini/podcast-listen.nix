# Obsidian → read-later podcast: every 15 minutes, queue Inbox notes tagged
# #listen on the podcast intake on nixos-infra (docs/PODCAST.md). The vault
# lives here, in the user's iCloud session, so this is a user LaunchAgent
# like the vault bridge, and it only runs while that session is up.
#
# Read-only on the vault: what has been sent is remembered in
# ~/Library/Application Support/podcast-listen/sent.json, never by editing
# the note. Remove a note's entry there to send it again (keep it valid
# JSON: no trailing comma after the last entry).
#
# Disable: remove ./podcast-listen.nix from default.nix imports and switch
# the mini; then drop podcast-intake-token from secrets/mini.yaml.
{
  username,
  pkgs,
  config,
  lib,
  ...
}: let
  # Same vault as the bridge in default.nix ("Pro Pilot 2" is the live one).
  vaultPath = "/Users/${username}/Library/Mobile Documents/iCloud~md~obsidian/Documents/Pro Pilot 2";
  stateFile = "/Users/${username}/Library/Application Support/podcast-listen/sent.json";
  # The tailnet-only intake on the podcast sidecar (nixos-infra podcast.nix).
  intake = "https://podcast.jaguar-duckbill.ts.net:8444/enqueue";
in {
  # Same value as podcast-intake-token in secrets/nixos-infra.yaml. Owned by
  # the login user because the agent runs in that user's session.
  sops.secrets.podcast-intake-token = {
    owner = username;
    mode = "0400";
  };

  launchd.user.agents.podcast-listen = {
    serviceConfig = {
      RunAtLoad = true;
      StartInterval = 900;
      StandardOutPath = "/Users/${username}/Library/Logs/podcast-listen.log";
      StandardErrorPath = "/Users/${username}/Library/Logs/podcast-listen.log";
    };
    script = ''
      set -eu
      PODCAST_INTAKE_TOKEN=$(${pkgs.coreutils}/bin/cat ${lib.escapeShellArg config.sops.secrets.podcast-intake-token.path})
      export PODCAST_INTAKE_TOKEN
      exec ${pkgs.python3.interpreter} ${./podcast-listen/watch.py} \
        ${lib.escapeShellArg vaultPath} ${lib.escapeShellArg stateFile} ${intake}
    '';
  };
}
