# Generic "nix-owned docker compose stack" module — darwin counterpart of
# modules/nixos/compose-stack.nix. Same option surface, same contract: the
# repo's compose file is AUTHORITATIVE, hand-edits to
# <stateDir>/docker-compose.yml are overwritten on the next activation, and
# services removed from the file are removed from the host
# (--remove-orphans).
#
# Three things differ from the NixOS module, all forced by macOS:
#
#  1. launchd user agent, not a system daemon. Container runtimes on macOS
#     (OrbStack, Colima) expose a user-owned socket from a per-user VM, so
#     the reconcile has to run as the primary user.
#  2. No restartTriggers. The generated script embeds the compose file's
#     store path, so a content change yields a new script path, a new plist,
#     and launchd reloads the agent — same effect, different mechanism.
#  3. The socket wait loop. The agent can fire at login before the runtime's
#     VM is up; on NixOS `requires = docker.service` handles this for free.
#
# The runtime is addressed only through `dockerHost`, so switching OrbStack
# -> Colima is a one-line change and touches nothing else.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.majordouble.composeStacks;
  user = config.majordouble.user;
in {
  options.majordouble.composeStacks = lib.mkOption {
    default = {};
    description = "Docker compose stacks deployed and reconciled by nix.";
    type = lib.types.attrsOf (lib.types.submodule ({name, ...}: {
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
        dockerHost = lib.mkOption {
          type = lib.types.str;
          default = "unix:///Users/${user}/.orbstack/run/docker.sock";
          description = ''
            Container runtime socket. Defaults to OrbStack's; point it at
            ~/.colima/default/docker.sock to switch to Colima.
          '';
        };
        logFile = lib.mkOption {
          type = lib.types.str;
          default = "/Users/${user}/Library/Logs/compose-${name}.log";
          description = "Combined stdout/stderr for the reconcile agent.";
        };
      };
    }));
  };

  config = {
    launchd.user.agents =
      lib.mapAttrs' (
        name: stack:
          lib.nameValuePair "compose-${name}" {
            # docker_29 matches the engine version on nixos-infra and, unlike
            # the default `docker` (28.5.2), carries no knownVulnerabilities.
            # Only the client is used here; the runtime is OrbStack's.
            path = [pkgs.docker_29 pkgs.docker-compose pkgs.coreutils];
            environment.DOCKER_HOST = stack.dockerHost;
            serviceConfig = {
              RunAtLoad = true;
              # Retry on failure only — a clean reconcile must not relaunch.
              KeepAlive.SuccessfulExit = false;
              ThrottleInterval = 30;
              StandardOutPath = stack.logFile;
              StandardErrorPath = stack.logFile;
            };
            script = ''
              set -eu

              # ~/.docker/config.json sets credsStore=osxkeychain, so every
              # registry request shells out to docker-credential-osxkeychain
              # — an OrbStack binary symlinked into /usr/local/bin, outside
              # the nix store. Without it on PATH, `up -d` fails at the pull
              # with "error getting credentials", but only when an image is
              # actually missing: once the images are local the agent exits
              # 0 and looks healthy right up until the next image bump.
              export PATH="$PATH:/usr/local/bin"

              mkdir -p ${lib.escapeShellArg stack.stateDir}
              install -m 0644 ${stack.composeFile} ${lib.escapeShellArg "${stack.stateDir}/docker-compose.yml"}

              # The runtime's VM may still be booting. Bounded wait (5 min);
              # exiting non-zero lets launchd retry rather than reconciling
              # against a socket that isn't there.
              tries=0
              until docker info >/dev/null 2>&1; do
                tries=$((tries + 1))
                if [ "$tries" -ge 60 ]; then
                  echo "docker socket ${stack.dockerHost} not ready after 5m" >&2
                  exit 1
                fi
                sleep 5
              done

              exec docker-compose \
                --project-directory ${lib.escapeShellArg stack.stateDir} \
                -f ${lib.escapeShellArg "${stack.stateDir}/docker-compose.yml"} \
                ${lib.optionalString (stack.envFile != null) "--env-file ${lib.escapeShellArg stack.envFile}"} \
                up -d --remove-orphans
            '';
          }
      )
      cfg;
  };
}
