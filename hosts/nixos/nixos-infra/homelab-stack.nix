# The /srv/homelab docker compose estate, deployed by nix via the
# compose-stack module. stacks/homelab/docker-compose.yml in the repo is
# authoritative — hand-edits on the VM are overwritten at switch.
# TS_AUTHKEY interpolation comes from the sops homelab-env secret
# (replaces the old /srv/homelab/.env).
{config, ...}: {
  majordouble.composeStacks.homelab = {
    composeFile = ../../../stacks/homelab/docker-compose.yml;
    stateDir = "/srv/homelab";
    envFile = config.sops.secrets.homelab-env.path;
  };
}
