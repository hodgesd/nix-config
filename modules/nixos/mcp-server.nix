# Generic "hardened MCP server" module (Phase 0 skeleton — no consumers yet).
#
# Each declared server gets a locked-down systemd service. This module owns
# the PROCESS side only; Hermes learns about a server through the upstream
# module's `services.hermes-agent.mcpServers.<name>` (url/headers, and the
# per-server `tools.include` allowlist — the tool catalog is the risk
# surface, so every consumer must set it explicitly).
#
# Network exposure model: the host firewall is already tailnet-only
# (nixos-common.nix), so nothing here is reachable from LAN/WAN even if a
# server binds 0.0.0.0. Servers should still bind localhost when only the
# co-located Hermes needs them — belt and suspenders, and it keeps them out
# of tailnet reach until an ACL decision is made deliberately.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.majordouble.mcpServers;
in {
  options.majordouble.mcpServers = lib.mkOption {
    default = {};
    description = "MCP servers run as hardened systemd services.";
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        command = lib.mkOption {
          type = lib.types.str;
          description = "Absolute path to the server executable (store path).";
        };
        args = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "Arguments (transport, bind address, port, …).";
        };
        environmentFile = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Env file for credentials — a sops secret path, never a repo file.";
        };
        readWritePaths = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "The ONLY paths the server may write (ProtectSystem=strict denies everything else). Empty for read-only integrations.";
        };
        description = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Human description shown in systemctl.";
        };
      };
    });
  };

  config = {
    systemd.services =
      lib.mapAttrs' (
        name: server:
          lib.nameValuePair "mcp-${name}" {
            description =
              if server.description != ""
              then server.description
              else "MCP server: ${name}";
            wantedBy = ["multi-user.target"];
            after = ["network-online.target"];
            wants = ["network-online.target"];
            serviceConfig = {
              ExecStart = lib.escapeShellArgs ([server.command] ++ server.args);
              Restart = "on-failure";
              RestartSec = 5;

              # Throwaway UID per service: no login, no home, no shared
              # group with hermes or other services — one compromised
              # server can't read another's state or the sops secrets.
              DynamicUser = true;
              EnvironmentFile = lib.mkIf (server.environmentFile != null) server.environmentFile;

              # Hardening baseline. Read-only / everywhere except the
              # explicit allowlist; no privilege escalation paths; only
              # plain sockets (no netlink/raw — an MCP server speaks HTTP
              # or stdio, nothing else).
              NoNewPrivileges = true;
              ProtectSystem = "strict";
              ProtectHome = true;
              ReadWritePaths = server.readWritePaths;
              PrivateTmp = true;
              PrivateDevices = true;
              ProtectKernelTunables = true;
              ProtectKernelModules = true;
              ProtectControlGroups = true;
              RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
              RestrictNamespaces = true;
              LockPersonality = true;
              MemoryDenyWriteExecute = true;
              CapabilityBoundingSet = "";
              SystemCallFilter = ["@system-service" "~@privileged"];
            };
          }
      )
      cfg;
  };
}
