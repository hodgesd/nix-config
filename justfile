# Build the system config and switch to it when running `just` with no args
default: switch

hostname := `hostname | cut -d "." -f 1`

### macos

# Set system name to a given argument and show old/new values
set-name name:
    @if [ -z "{{name}}" ]; then
        echo "❌ Error: hostname cannot be empty"
        echo "Usage: set-name <hostname>"
        exit 1
    fi
    echo "🔍 Current hostname values:"
    echo -n "ComputerName:     " && scutil --get ComputerName || echo "(not set)"
    echo -n "LocalHostName:    " && scutil --get LocalHostName || echo "(not set)"
    echo -n "HostName:         " && scutil --get HostName || echo "(not set)"
    echo -n "hostname (shell): " && hostname
    echo "\n⚙️  Setting all hostnames to '{{name}}'..."
    sudo scutil --set ComputerName "{{name}}"
    sudo scutil --set LocalHostName "{{name}}"
    sudo scutil --set HostName "{{name}}"
    echo "\n✅ Updated hostname values:"
    echo -n "ComputerName:     " && scutil --get ComputerName
    echo -n "LocalHostName:    " && scutil --get LocalHostName
    echo -n "HostName:         " && scutil --get HostName
    echo -n "hostname (shell): " && hostname

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
  ./result/sw/bin/darwin-rebuild switch --flake ".#{{target_host}}"

### linux
# Build the NixOS configuration without switching to it
[linux]
build target_host=hostname flags="":
	nixos-rebuild build --flake .#{{target_host}} {{flags}}

# Build the NixOS config with the --show-trace flag set
[linux]
trace target_host=hostname: (build target_host "--show-trace")

# Build the NixOS configuration and switch to it.
[linux]
switch target_host=hostname:
  sudo nixos-rebuild switch --flake .#{{target_host}}

## colmena
cbuild:
  colmena build

capply:
  colmena apply

# Update flake inputs to their latest revisions
update:
  nix flake update

## remote nix vm installation
install IP:
  ssh -o "StrictHostKeyChecking no" nixos@{{IP}} "sudo bash -c '\
    nix-shell -p git --run \"cd /root/ && \
    if [ -d \"nix-config\" ]; then \
        rm -rf nix-config; \
    fi && \
    git clone https://github.com/ironicbadger/nix-config.git && \
    cd nix-config/lib/install && \
    sh install-nix.sh\"'"


# Garbage collect old OS generations and remove stale packages from the nix store
gc generations="5":
  nix-env --delete-generations {{generations}}
  nix-store --gc
