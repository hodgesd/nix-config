#!/usr/bin/env bash
# bootstrap.sh — take a fresh macOS machine to a fully-activated nix-darwin config.
#
# Usage:
#   ./scripts/bootstrap.sh [hostname]
#
# hostname defaults to `hostname -s` and must be one of the flake's
# darwinConfigurations (currently: mbp, mini, air, studio). On a brand-new Mac:
#
#   1. Install git via the Xcode CLT prompt (or let this script do it),
#   2. git clone https://github.com/hodgesd/nix-config && cd nix-config
#   3. ./scripts/bootstrap.sh <host>
#
# Idempotent: safe to re-run. Skips anything already in place.
set -euo pipefail

# The repo root is the script's parent. (This used to point at scripts/ and
# worked only because modern Nix searches upwards for flake.nix.)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
  # Bounded: if the GUI dialog is dismissed, this used to spin forever.
  tries=0
  until /usr/bin/xcode-select -p >/dev/null 2>&1; do
    sleep 5
    tries=$((tries + 1))
    if [ "$tries" -ge 240 ]; then
      die "Command Line Tools still missing after 20 minutes. Finish (or
     re-trigger) the installer, then re-run this script."
    fi
  done
fi

# 2. Nix — UPSTREAM Nix, via the Determinate Systems installer.
#
# `--prefer-upstream-nix` is load-bearing, not a preference. Since
# 2026-01-01 this installer defaults to *Determinate Nix*, a separate
# distribution that runs its own daemon at /usr/local/bin/determinate-nixd.
# nix-darwin 26.05 detects that file and HARD-ABORTS activation ("error:
# Determinate detected, aborting activation", exit 2) unless you set
# `nix.enable = false` — which would switch off the `nix.*` options this
# repo depends on (lib/helpers.nix sets nix.settings.trusted-users and
# experimental-features for every darwin host) and would diverge this Mac
# from mbp/mini/air, which were installed before the default flipped.
#
# Upstream Nix is explicitly "not a supported configuration" for this
# installer and the flag may be withdrawn. If it ever disappears, use
# upstream's own installer instead:
#     sh <(curl -L https://nixos.org/nix/install) --daemon
# Adopting Determinate across the whole fleet is the other legitimate
# answer, but it is a deliberate migration (move nix.settings into
# /etc/nix/nix.custom.conf), not something to discover mid-bootstrap.
if ! command -v nix >/dev/null 2>&1; then
  log "Installing upstream Nix (Determinate Systems installer)…"
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
    | sh -s -- install --no-confirm --prefer-upstream-nix
fi

# Fail fast and legibly if Determinate Nix is present anyway — installed by
# hand, by a teammate, or because the flag above stopped working. Otherwise
# this surfaces as an abort deep inside activation, after the cask storm.
if [ -e /usr/local/bin/determinate-nixd ]; then
  die "Determinate Nix is installed (/usr/local/bin/determinate-nixd), which
     nix-darwin refuses to activate alongside its own Nix management.

     Either remove it and re-run with upstream Nix, or adopt Determinate
     deliberately across the fleet by setting nix.enable = false and moving
     lib/helpers.nix's nix.settings into /etc/nix/nix.custom.conf.
     See the comment above this check for the full reasoning."
fi

# Make nix available in this shell session (installer sets it up for new shells).
if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi
command -v nix >/dev/null 2>&1 \
  || die "nix is not on PATH after install. Open a new terminal and re-run ./scripts/bootstrap.sh $host"

# 3. Validate the requested host exists in the flake
log "Validating host '$host'…"
if ! "${NIX[@]}" eval --raw ".#darwinConfigurations.${host}.system.drvPath" >/dev/null 2>&1; then
  avail="$("${NIX[@]}" eval --json '.#darwinConfigurations' --apply builtins.attrNames 2>/dev/null \
            | tr -d '[]"' | tr ',' ' ')"
  die "'$host' is not a known host. Available:${avail:- mbp mini air studio}
     Pass one explicitly:  ./scripts/bootstrap.sh <host>"
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
