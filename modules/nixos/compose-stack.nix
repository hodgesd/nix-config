# Generic "nix-owned docker compose stack" module.
#
# Each declared stack gets a oneshot systemd unit that installs the
# repo's compose file into the stack's state dir and runs
# `docker compose up -d --remove-orphans`. The compose file in the repo
# is AUTHORITATIVE: hand-edits to <stateDir>/docker-compose.yml on the
# host are overwritten on the next switch, and services removed from the
# file are removed from the host (--remove-orphans).
#
# The unit re-runs only when the compose file (or this module) changes —
# restartTriggers carries the store path, which changes with content.
# Volumes/bind mounts persist across container recreation; recreation
# happens only when a service's config (image, env, mounts, …) changes.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.majordouble.composeStacks;
in {
  options.majordouble.composeStacks = lib.mkOption {
    default = {};
    description = "Docker compose stacks deployed and reconciled by nix.";
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        composeFile = lib.mkOption {
          type = lib.types.path;
          description = "Compose file (repo copy — authoritative).";
        };
        stateDir = lib.mkOption {
          type = lib.types.str;
          description = "Project directory; relative ./ volumes resolve here.";
        };
        envFile = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Optional env file for compose interpolation (e.g. a sops secret path).";
        };
      };
    });
  };

  config = {
    systemd.services =
      lib.mapAttrs' (
        name: stack:
          lib.nameValuePair "compose-${name}" {
            description = "docker compose stack: ${name}";
            wantedBy = ["multi-user.target"];
            requires = ["docker.service"];
            after = ["docker.service" "network-online.target"];
            wants = ["network-online.target"];
            path = [config.virtualisation.docker.package];
            restartTriggers = [stack.composeFile];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            script = ''
              mkdir -p ${stack.stateDir}
              install -m 0644 ${stack.composeFile} ${stack.stateDir}/docker-compose.yml
              docker compose --project-directory ${stack.stateDir} \
                ${lib.optionalString (stack.envFile != null) "--env-file ${stack.envFile}"} \
                up -d --remove-orphans
            '';
          }
      )
      cfg;
  };
}
