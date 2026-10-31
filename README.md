# nix-config

[![Eval](https://github.com/hodgesd/nix-config/actions/workflows/eval.yaml/badge.svg)](https://github.com/hodgesd/nix-config/actions/workflows/eval.yaml)
[![Build](https://github.com/hodgesd/nix-config/actions/workflows/build.yaml/badge.svg)](https://github.com/hodgesd/nix-config/actions/workflows/build.yaml)

One Nix flake for every machine I own: four Macs on nix-darwin and two NixOS
VMs on the HP mini PC's Proxmox host. One lockfile, shared modules, and a
registry in `lib/machines.nix` whose fields (type, form factor, role, chip,
user) drive every per-host branch. Hosts reach each other only over
Tailscale. CI evaluates every host on each push and pushes closures to
Cachix.

## Fleet

| Host | Machine | Role | Activate | Config |
|---|---|---|---|---|
| `mbp` | MacBook Pro 14" M3 Pro, 18 GB / 1 TB | daily driver; NAS backup, Gulfstream pubs watcher | `just`, on the box | `hosts/darwin/mbp/` |
| `mini` | Mac mini M2 Pro, user `derrickhodges` | always-on; Hermes bridges (vault-mcp, apple-mcp) | `just`, on the box only | `hosts/darwin/mini/` |
| `air` | MacBook Air 13" M1, 16 GB / 500 GB | spare laptop | `just`, on the box | common only |
| `studio` | Mac Studio M5 Ultra, 96 GB / 2 TB | local AI inference (Ollama on the tailnet) | `just`, on the box | `hosts/darwin/studio/` |
| `nixos-infra` | Proxmox VM, 2 vCPU, 39 GB disk | homelab: Docker apps behind tailnet sidecars, Gatus, Hermes, easy-afd, 21.hdgs.me, agent workbench | `just deploy`, from a Mac | `hosts/nixos/nixos-infra/` |
| `t3-code` | Proxmox VM 101, 4 vCPU, 12 GB / 64 GB | T3 Code remote server, kept apart from the homelab | `just deploy t3-code switch <ssh-dest>` | `hosts/nixos/t3-code/` |

## Get started

**New Mac.** The hostname must be a darwin host above. The script installs
the Xcode CLT and Nix, builds, and activates. It is safe to re-run.

```bash
git clone https://github.com/hodgesd/nix-config.git ~/nix-config
cd ~/nix-config && ./scripts/bootstrap.sh <hostname>
```

**Mac with apps and data to keep.** Read [docs/MAC-SETUP.md](docs/MAC-SETUP.md)
first. It covers the pre-install audit, Homebrew cleanup mode, and the
one-time toggles after the first switch.

**Homelab, from a Mac.** The Mac evaluates, the VM builds and activates over
Tailscale SSH.

```bash
just deploy-check   # dry-activate: show what would change
just deploy         # activate nixos-infra
```

## Everyday

| Command | Does |
|---|---|
| `just` | build and switch this Mac |
| `just build` / `just trace` | build only / build with `--show-trace` |
| `just deploy-check` / `just deploy` | dry-activate / activate nixos-infra |
| `just update` | bump every input on the 26.05 release branches |
| `just gc [days]` | drop generations older than 14 days, optimise the store |
| `nix fmt <paths>` | format; see the note below |

Rollback is `darwin-rebuild switch --rollback` on a Mac and
`sudo nixos-rebuild switch --rollback` on a VM.

Pass `nix fmt` explicit paths. Bare `nix fmt` makes alejandra read stdin and
fail on nix 2.34+, and `nix fmt .` would reformat the
`hardware-configuration.nix` files, which must stay byte-for-byte as
generated.

Inputs: nixpkgs, nix-darwin and Home Manager track the 26.05 release
branches, and `nixpkgs-unstable` supplies anything that must be fresh. The
rest are sops-nix, nix-homebrew, hermes-agent, llm-agents, bj-drill and
swiftbar_plugins. Renovate opens a weekly PR for the homelab images and one
for the lockfile.

## Secrets

sops-nix. Ciphertext lives in `secrets/<host>.yaml` and is safe in git.
Recipients are in `.sops.yaml`: the Mac editing key plus each host's SSH host
key. Hosts decrypt to `/run/secrets` at activation, and a decrypt failure
aborts before any service restarts. Edit with `sops secrets/<host>.yaml`.

## Go deeper

| I want to… | Read |
|---|---|
| understand the layout and how a host is assembled | [docs/STRUCTURE.md](docs/STRUCTURE.md) |
| add a machine | [docs/ADDING_MACHINE.md](docs/ADDING_MACHINE.md) |
| set up or migrate a Mac, run the audits | [docs/MAC-SETUP.md](docs/MAC-SETUP.md) |
| change packages, macOS defaults, hotkeys, Homebrew | [docs/CUSTOMIZATION.md](docs/CUSTOMIZATION.md), [docs/HOMEBREW.md](docs/HOMEBREW.md) |
| operate or recover the homelab | [docs/NIXOS-INFRA.md](docs/NIXOS-INFRA.md), [status board](https://status.jaguar-duckbill.ts.net) |
| run models on the studio | [docs/studio/](docs/studio/) |
| work on Hermes | [docs/hermes/](docs/hermes/) |
| Home Assistant, HN summaries, the Gatus decision | [HOME-ASSISTANT.md](docs/HOME-ASSISTANT.md), [HN-SUMMARIES.md](docs/HN-SUMMARIES.md), [GATUS-EVAL.md](docs/GATUS-EVAL.md) |
| CI, Cachix, Renovate | [.github/workflows/README.md](.github/workflows/README.md) |
