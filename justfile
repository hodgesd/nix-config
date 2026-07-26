# Build the system config and switch to it when running `just` with no args
default: switch

hostname := `hostname | cut -d "." -f 1`

### macos

# Build the nix-darwin system configuration without switching to it
[macos]
build target_host=hostname flags="":
  @echo "Building nix-darwin config..."
  nix --extra-experimental-features 'nix-command flakes'  build ".#darwinConfigurations.{{target_host}}.system" {{flags}}

# Build the nix-darwin config with the --show-trace flag set
[macos]
trace target_host=hostname: (build target_host "--show-trace")

# Build the nix-darwin configuration and switch to it
[macos]
switch target_host=hostname: (build target_host)
  @echo "switching to new config for {{target_host}}"
  sudo ./result/sw/bin/darwin-rebuild switch --flake ".#{{target_host}}"

### nixos (run from the Mac)

# Deploy a nixos host: eval locally, build + activate on the host over tailscale.
# The Mac can't build x86_64-linux, so the derivation closure is copied to the
# host and realised there (CI-pushed Cachix closures make that mostly
# downloads). Activation runs inside a transient systemd unit so it survives
# tailscaled restarts mid-switch. ssh_dest is root over Tailscale SSH
# (tailscaled's own SSH server — unaffected by openssh's PermitRootLogin=no),
# so no sudo password is needed. The bare hostname resolves to the LAN IP
# where root login is refused, hence the tailnet IP default.
[macos]
deploy target_host="nixos-infra" action="switch" ssh_dest="root@100.98.163.36":
  #!/usr/bin/env bash
  set -euo pipefail
  echo "==> evaluating {{target_host}}"
  drv=$(nix eval --raw ".#nixosConfigurations.{{target_host}}.config.system.build.toplevel.drvPath")
  echo "==> copying derivations to {{ssh_dest}}"
  nix copy --derivation --to "ssh://{{ssh_dest}}" "$drv"
  echo "==> realising on {{ssh_dest}} (Cachix/cache.nixos.org downloads + local builds)"
  out=$(ssh {{ssh_dest}} "nix-store --realise '$drv'")
  echo "==> {{action}} $out"
  if [ "{{action}}" = "switch" ] || [ "{{action}}" = "boot" ]; then
    ssh {{ssh_dest}} "nix-env -p /nix/var/nix/profiles/system --set '$out'"
    ssh {{ssh_dest}} "systemd-run --wait --collect --quiet --unit=nixos-deploy \
      '$out/bin/switch-to-configuration' {{action}}" \
      || { echo 'activation unit failed; check: journalctl -u nixos-deploy'; exit 1; }
    ssh {{ssh_dest}} "readlink /run/current-system"
  else
    ssh {{ssh_dest}} "'$out/bin/switch-to-configuration' {{action}}"
  fi

# Dry-run a deploy (shows would-be systemd changes on the host)
[macos]
deploy-check target_host="nixos-infra": (deploy target_host "dry-activate")

# DR fallback, run on a nixos host itself: git pull then switch
[linux]
switch-nixos:
  sudo nixos-rebuild switch --flake ".#$(hostname)"

# Update flake inputs to their latest revisions
update:
  nix flake update

# Garbage collect system generations older than N days and optimise the store
gc days="14":
  sudo nix-collect-garbage --delete-older-than {{days}}d
  nix-store --optimise
