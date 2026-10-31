# Phase 3 — studio: Ollama serving

**Status: config landed 2026-10-30; runtime verification PENDING the first
`darwin-rebuild switch` on studio.** The measurements section below is
deliberately empty rather than guessed — Phase 3b compares against it.

## What was built

`hosts/darwin/studio/default.nix`:

| Thing | Detail |
|---|---|
| Package | `unstablePkgs.ollama` — **0.34.3** at our locked rev, past the 0.19 that added the Apple-silicon MLX backend. No brew fallback needed. |
| CLI | `environment.systemPackages = [ollama]` — same store path as the daemon, so `ollama ps` can never talk to a different build |
| Service | `launchd.daemons.ollama` → label `org.nixos.ollama` |
| Bind | `OLLAMA_HOST = 127.0.0.1:11434` — loopback only |
| Residency | `OLLAMA_KEEP_ALIVE = 30m`, `OLLAMA_MAX_LOADED_MODELS = 2` |
| Logs | `~/Library/Logs/ollama.log` |

### Why a system daemon and not a user agent

This is the Phase 3 decision, and it follows from FileVault being off.
The box boots to loginwindow unattended, and a **system daemon starts
there with nobody logged in** — so an unattended reboot comes back
serving. `launchd.user.agents` (the mini's pattern) would wait for a
login session. The third option, user agent plus auto-login, buys the
same outcome at the price of an always-unlocked desktop, so it is the
fallback rather than the default.

`UserName = "hodgesd"` rather than root: least privilege, and it keeps
the model store in `~` where the Phase 1 Time Machine and Spotlight
exclusions already point. That works *because* FileVault is off — the
data volume is never gated, so a pre-login daemon can read `~`.

### The non-obvious bit: `HOME` and `OLLAMA_MODELS`

A LaunchDaemon does **not** inherit a usable `HOME` just because
`UserName` is set. Left unset, Ollama picks a different models directory
— outside `~/.ollama`, therefore outside the Phase 1 backup and Spotlight
exclusions — and nothing looks broken. Both variables are set explicitly.
Do not "simplify" them away.

## Manual steps (not Nix)

```bash
# 1. Activate
cd ~/nix-config && git pull && sudo darwin-rebuild switch --flake .#studio

# 2. One-time tailnet route — state, not config, same as the mini's bridges
tailscale serve --bg --https=11434 http://127.0.0.1:11434

# 3. Something to benchmark
ollama pull <model>
```

## How to verify

```bash
# Service up, one owner, correct label
sudo launchctl print system/org.nixos.ollama | head -20
lsof -i :11434                      # exactly one listener

# Loopback only: must ANSWER on localhost and REFUSE on the LAN address
curl -s localhost:11434/api/version
curl -s --max-time 5 http://192.168.1.198:11434/api/version   # must fail

# From another tailnet node
curl -s https://studio.<tailnet>.ts.net:11434/api/version
curl -s https://studio.<tailnet>.ts.net:11434/v1/models

# Models landed in the exclusion-covered path, not somewhere else
ollama list && ls ~/.ollama/models
```

**The real test** — not "is the process running":

```bash
sudo reboot
# then, WITHOUT logging in at the screen, from another machine:
ssh hodgesd@studio 'curl -s localhost:11434/api/version && ollama run <model> "say hi"'
```

A generation completing with no session is what justifies the daemon
branch. If Metal is unreachable pre-login, fall back per the ordering in
the plan's CONTEXT (non-GUI user domain, then user agent + auto-login)
and say so plainly rather than shipping something fragile.

## How to disable

Comment out the `launchd.daemons.ollama` block and rebuild, then
`tailscale serve --https=11434 off` to retract the tailnet route. The CLI
stays until `environment.systemPackages` is also trimmed.

## Measurements — PENDING

Fill after the switch; Phase 3b measures oMLX against these.

| Metric | Value |
|---|---|
| Model used | |
| Backend named in the log (MLX vs Metal/GGML) | |
| Cold TTFT | |
| Tokens/s, steady state | |

## Manual test script (5 items)

1. `sudo launchctl print system/org.nixos.ollama` → running, `UserName hodgesd`.
2. `curl localhost:11434/api/version` answers; the same curl against
   `192.168.1.198` refuses. (Loopback discipline — security rule 1.)
3. `kill` the process; it comes back within ~15s (KeepAlive + ThrottleInterval).
4. `ollama list` after a pull, and `ls ~/.ollama/models` is non-empty —
   proves `OLLAMA_MODELS` took and the models are inside the Phase 1
   exclusions.
5. Reboot without logging in, then generate over SSH. This is the one that
   decides whether the daemon branch was right.
