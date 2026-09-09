# The /srv/homelab docker compose estate, deployed by nix via the
# compose-stack module. stacks/homelab/docker-compose.yml in the repo is
# authoritative — hand-edits on the VM are overwritten at switch.
# Compose interpolation reads a sops template that joins the homelab-env
# secret (TS_AUTHKEY for the tailscale sidecars, replaces the old
# /srv/homelab/.env) with per-app tokens kept as their own sops keys.
{config, ...}: {
  sops.templates.homelab-env.content = ''
    ${config.sops.placeholder.homelab-env}
    HOMEPAGE_MCP_TOKEN=${config.sops.placeholder.homepage-mcp-token}
  '';

  majordouble.composeStacks.homelab = {
    composeFile = ../../../stacks/homelab/docker-compose.yml;
    stateDir = "/srv/homelab";
    envFile = config.sops.templates.homelab-env.path;
  };
}
