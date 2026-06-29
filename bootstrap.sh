#!/usr/bin/env bash
# bootstrap.sh — take a fresh macOS machine to a fully-activated nix-darwin config.
#
# Usage:
#   ./bootstrap.sh [hostname]
#
# hostname defaults to `hostname -s` and must be one of the flake's
# darwinConfigurations (currently: mbp, mini, air). On a brand-new Mac:
#
#   1. Install git via the Xcode CLT prompt (or let this script do it),
#   2. git clone https://github.com/hodgesd/nix-config && cd nix-config
#   3. ./bootstrap.sh <host>
#
# Idempotent: safe to re-run. Skips anything already in place.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

host="${1:-$(hostname -s)}"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Run nix with flakes on, even before the daemon config enables them.
NIX=(nix --extra-experimental-features "nix-command flakes")

# 1. Xcode Command Line Tools (provides git, cc, etc.)
if ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
  log "Installing Xcode Command Line Tools (a GUI dialog will appear)…"
  /usr/bin/xcode-select --install || true
  log "Waiting for Command Line Tools to finish installing…"
  until /usr/bin/xcode-select -p >/dev/null 2>&1; do sleep 5; done
fi

# 2. Nix — Determinate Systems installer (matches CI; enables flakes by default)
if ! command -v nix >/dev/null 2>&1; then
  log "Installing Nix (Determinate Systems installer)…"
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
    | sh -s -- install --no-confirm
fi

# Make nix available in this shell session (installer sets it up for new shells).
if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi
command -v nix >/dev/null 2>&1 \
  || die "nix is not on PATH after install. Open a new terminal and re-run ./bootstrap.sh $host"

# 3. Validate the requested host exists in the flake
log "Validating host '$host'…"
if ! "${NIX[@]}" eval --raw ".#darwinConfigurations.${host}.system.drvPath" >/dev/null 2>&1; then
  avail="$("${NIX[@]}" eval --json '.#darwinConfigurations' --apply builtins.attrNames 2>/dev/null \
            | tr -d '[]"' | tr ',' ' ')"
  die "'$host' is not a known host. Available:${avail:- mbp mini air}
     Pass one explicitly:  ./bootstrap.sh <host>"
fi

# 4. Build, then activate.
#    First run: darwin-rebuild isn't installed yet, so build the system and run
#    its bundled darwin-rebuild (same pattern as the justfile). Later runs use
#    the installed darwin-rebuild directly.
if command -v darwin-rebuild >/dev/null 2>&1; then
  log "Activating '$host' with installed darwin-rebuild (sudo)…"
  sudo darwin-rebuild switch --flake ".#${host}"
else
  log "First activation: building '$host'…"
  "${NIX[@]}" build ".#darwinConfigurations.${host}.system"
  log "Activating '$host' (sudo)…"
  sudo ./result/sw/bin/darwin-rebuild switch --flake ".#${host}"
  rm -f result
fi

log "Done. '$host' is activated."
log "Open a new terminal so the new shell environment takes effect."
