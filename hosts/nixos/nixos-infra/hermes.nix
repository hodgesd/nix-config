# Hermes Agent (NousResearch) in container mode on the existing Docker
# daemon. The upstream module creates the hermes user/group, runs the agent
# container, and routes the host `hermes` CLI into it via ~/.hermes +
# .container-mode marker for the listed hostUsers.
{
  inputs,
  config,
  ...
}: {
  imports = [inputs.hermes-agent.nixosModules.default];

  # The hermes module hardcodes ${pkgs.docker}/bin/docker (no package
  # option), and 25.11's default docker (28.5.2) is marked insecure. This
  # host already runs docker_29 (nixos-common.nix); make pkgs.docker mean
  # the same thing so the module's CLI matches the running daemon.
  nixpkgs.overlays = [(final: prev: {docker = prev.docker_29;})];

  # ANTHROPIC_API_KEY, dotenv format. Root-read is fine: systemd resolves
  # EnvironmentFiles as root (same pattern as easy-afd-env).
  sops.secrets.hermes-env = {};

  services.hermes-agent = {
    enable = true;
    container.enable = true;
    container.hostUsers = ["hodgesd"];
    addToSystemPackages = true;
    extraDependencyGroups = ["messaging"];
    settings = {
      model.default = "claude-sonnet-4-5";
      model.base_url = "https://api.anthropic.com/v1";
      terminal = {
        backend = "local";
        timeout = 180;
      };
    };
    environmentFiles = [config.sops.secrets.hermes-env.path];
  };
}
