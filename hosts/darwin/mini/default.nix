# Host-specific configuration for mini (M2 Pro desktop, primaryUse = "server").
#
# The mini is an unattended box: it hosts the Hermes bridges (vault-mcp,
# apple-mcp), so everything below exists so it comes back on its own after
# a reboot or a power cut, with nobody at the keyboard. (It hosted Uptime
# Kuma from 2026-08-08 until Gatus replaced it on 2026-09-06 — see
# hosts/nixos/nixos-infra/gatus.nix and docs/GATUS-EVAL.md.)
{
  username,
  pkgs,
  config,
  lib,
  ...
}: let
  # Phase 1 (Hermes): path-jailed vault MCP server. Loopback only; the
  # tailnet reaches it via `tailscale serve --bg --https=8321
  # http://127.0.0.1:9102` (one-time, persisted in tailscaled state).
  vaultMcpEnv = pkgs.python3.withPackages (ps: [ps.fastmcp ps.httpx]);
  # "Pro Pilot 2" is the live vault (376 notes; confirmed 2026-08-30 —
  # there is no vault named "Derrick", and "Pro Pilot" is a stale husk).
  vaultPath = "/Users/${username}/Library/Mobile Documents/iCloud~md~obsidian/Documents/Pro Pilot 2";
in {
  # Whisper STT for Hermes' voice path — large-v3 on Metal, loopback
  # only, reached over the tailnet like the two bridges below. Moved off
  # the 8GB CPU-only VM for transcription ACCURACY, not speed. Read that
  # file's header before rebooting this box: it adds a voice-path
  # dependency on the mini being unlocked.
  imports = [./whisper-stt.nix];

  # NO auto-login here, deliberately. The bridges are *user* LaunchAgents
  # (they live in the user's iCloud session), so they only start once a GUI
  # session exists — and FileVault is on, which means macOS gates boot at
  # the pre-boot unlock screen and ignores
  # system.defaults.loginwindow.autoLoginUser entirely. Setting it would
  # imply reboots are handled when they are not.
  #
  # Consequence, worth knowing before you reboot this box:
  #   - Planned reboots: `sudo fdesetup authrestart` pre-authorizes the
  #     unlock, so the mini comes back to a live session unattended.
  #   - Unexpected power cut: it stops at the unlock screen and the bridges
  #     stay down until someone types the password. Gatus on nixos-infra
  #     pings this box and the Hermes sentinel checks the bridges, so ntfy
  #     is what tells you that has happened.

  # sops on this host: the bridges' bearer tokens. Decrypted at activation
  # using the mini's SSH host key (the .sops.yaml host_mini recipient);
  # owner = the login user because the servers run as launchd USER agents
  # (iCloud files belong to the session).
  sops = {
    defaultSopsFile = ../../../secrets/mini.yaml;
    age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
    secrets.vault-mcp-token = {
      owner = username;
      mode = "0400";
    };
    secrets.apple-mcp-token = {
      owner = username;
      mode = "0400";
    };
  };

  # Phase 4: the Apple bridge (apple-mcp/server.py) — Reminders writes
  # staged to the "Hermes Review" list only, Calendar read-only in v1.
  # Reads via icalBuddy (brew; EventKit), writes via /usr/bin/osascript.
  # WHY the start script runs under Apple's /bin/bash: TCC charges this
  # agent's Calendar/Reminders access to the start script's interpreter,
  # not to icalBuddy. Under Nix bash the grant was tied to a store path,
  # so bash 5.3p3 -> 5.3p9 dropped it and the brief said "No calendars"
  # (2026-11-07). /bin/bash is Apple-signed and keeps its grant across
  # updates. Trade-off: the grant covers any launchd job whose script runs
  # under /bin/bash (all ours). See the TCC runbook in docs/hermes/phase-4.md.
  launchd.user.agents.apple-mcp = {
    path = [vaultMcpEnv pkgs.coreutils];
    serviceConfig = {
      RunAtLoad = true;
      KeepAlive = true;
      ThrottleInterval = 15;
      # Same App Nap lesson as vault-mcp: without this, SSE never flushes.
      ProcessType = "Interactive";
      StandardOutPath = "/Users/${username}/Library/Logs/apple-mcp.log";
      StandardErrorPath = "/Users/${username}/Library/Logs/apple-mcp.log";
    };
    # Not `script =`: nix-darwin would give it a Nix bash shebang.
    command = toString (pkgs.writeScript "apple-mcp-start" ''
      #!/bin/bash
      set -eu
      APPLE_MCP_TOKEN=$(cat ${lib.escapeShellArg config.sops.secrets.apple-mcp-token.path})
      export APPLE_MCP_TOKEN
      exec python3 ${./apple-mcp/server.py} 9103
    '');
  };

  # The vault MCP server (vault-mcp/server.py — the whole tool surface,
  # reviewed as one file). User agent for the same reason as the compose
  # module: the vault is in the user's iCloud session. KeepAlive: a crash
  # relaunches; a reboot resumes at login (accepted mini trade-off above).
  launchd.user.agents.vault-mcp = {
    path = [vaultMcpEnv pkgs.coreutils];
    serviceConfig = {
      RunAtLoad = true;
      KeepAlive = true;
      ThrottleInterval = 15;
      # Without this, App Nap throttles the agent's asyncio loop: uvicorn
      # accepts and logs requests but SSE responses never flush — clients
      # hang while the server's log looks healthy. Diagnosed by running
      # the identical binary manually (worked) vs under launchd (hung).
      ProcessType = "Interactive";
      StandardOutPath = "/Users/${username}/Library/Logs/vault-mcp.log";
      StandardErrorPath = "/Users/${username}/Library/Logs/vault-mcp.log";
    };
    script = ''
      set -eu
      VAULT_MCP_TOKEN=$(cat ${lib.escapeShellArg config.sops.secrets.vault-mcp-token.path})
      export VAULT_MCP_TOKEN
      exec python3 ${./vault-mcp/server.py} ${lib.escapeShellArg vaultPath} 9102
    '';
  };

  # Come back by itself after a power cut or a panic (to the unlock screen,
  # per above), and never sleep out from under the monitors.
  power = {
    restartAfterPowerFailure = true;
    restartAfterFreeze = true;
    sleep = {
      computer = "never";
      display = 30;
      harddisk = "never";
    };
  };
}
