#!/usr/bin/env bash
# bootstrap.sh — take a fresh macOS machine to a fully-activated nix-darwin config.
#
# Usage:
#   ./scripts/bootstrap.sh [hostname]
#
# hostname defaults to `hostname -s` and must be one of the flake's
# darwinConfigurations (currently: mbp, mini, air). On a brand-new Mac:
#
#   1. Install git via the Xcode CLT prompt (or let this script do it),
#   2. Give the Mac read access to github.com/hodgesd/billfiler -- flake.nix
#      has it as a private git+ssh input and nix fetches every input eagerly,
#      so NO host evaluates without it (the clone below is https and does not
#      need this; the eval in step 3 does):
#        ssh-keygen -t ed25519 -C "$(hostname -s)"
#        ssh -T git@github.com     # accept github.com's host key
#        # then add ~/.ssh/id_ed25519.pub at https://github.com/settings/keys
#   3. git clone https://github.com/hodgesd/nix-config && cd nix-config
#   4. ./scripts/bootstrap.sh <host>
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
if ! err="$("${NIX[@]}" eval --raw ".#darwinConfigurations.${host}.system.drvPath" 2>&1 >/dev/null)"; then
  # Guarded, not bare: `set -e` plus `pipefail` makes a failed `nix eval` abort
  # the script right here, and this assignment is in the body of an if, not its
  # condition, so nothing protects it. That abort would skip the diagnostic
  # below -- the one case it exists to explain -- leaving a fresh Mac with
  # "Validating host 'mbp'..." and a bare exit 1.
  if ! avail="$("${NIX[@]}" eval --json '.#darwinConfigurations' --apply builtins.attrNames 2>/dev/null \
              | tr -d '[]"' | tr ',' ' ')"; then
    avail=""
  fi
  # Two unrelated failures land here and this block used to report both as the
  # first: a wrong hostname, and a flake that cannot be evaluated at all.
  # An empty $avail separates them -- listing the hosts needs the same
  # evaluation, so if that worked, the name really is wrong.
  #
  # The second case arrived with the private billfiler input: nix fetches every
  # flake input eagerly, so a Mac without read access to that repo cannot
  # evaluate ANY host. The old code hid the cause with 2>/dev/null and then
  # fell back to a hardcoded list, printing "'mbp' is not a known host.
  # Available: mbp mini air" -- which names the host as both unknown and
  # available, on a fresh machine where nothing else works yet either.
  if [ -z "$avail" ]; then
    die "the flake itself could not be evaluated, so host '$host' was never checked.

     Usually this is the private input: flake.nix pulls
     github.com/hodgesd/billfiler over git+ssh, and nix fetches every input
     eagerly, so no host evaluates until this Mac can read it:
       ssh-keygen -t ed25519 -C \"$host\"
       ssh -T git@github.com     # accept github.com's host key
       # then add ~/.ssh/id_ed25519.pub at https://github.com/settings/keys

     nix said:
$err"
  fi
  die "'$host' is not a known host. Available: $avail
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
