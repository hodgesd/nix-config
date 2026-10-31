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
| Bind | `OLLAMA_HOST = studio.jaguar-duckbill.ts.net:11434` — tailscale interface only |
| Residency | `OLLAMA_KEEP_ALIVE = 30m`, `OLLAMA_MAX_LOADED_MODELS = 2` |
| Logs | `~/Library/Logs/ollama.log` |

### Why it binds the MagicDNS name, not loopback

The mini's bridges use loopback + `tailscale serve`. Ollama can't: it
validates the HTTP **Host header** (DNS-rebinding protection) against
localhost plus whatever `OLLAMA_HOST` names, and `tailscale serve`
forwards the *original* Host — so every proxied request arrived as
`studio.jaguar-duckbill.ts.net` and got **403**.

Measured, not assumed: a `Host: 127.0.0.1` override returned 200 through
the same proxy; `OLLAMA_ORIGINS` (tested with the tailnet name, a bare
host, and `*`) does not affect it — that governs CORS only; and
`tailscale serve` has no Host-rewrite flag.

Binding the MagicDNS name makes the Host match while keeping the property
that matters: the socket is on the tailscale interface alone, so nothing
is on the LAN or the internet, and WireGuard already encrypts transport.
The loopback-preserving alternative (a Host-rewriting Caddy in front) was
rejected as an extra daemon buying no reduction in exposure.

**Dependency this creates:** the bind now needs tailscaled to have
assigned the address. Verified behaviour — Ollama exits immediately with
`bind: can't assign requested address` rather than hanging, so KeepAlive
+ `ThrottleInterval = 15` retries until it succeeds. Self-healing. Open
question for the reboot test: whether Tailscale on macOS comes up without
a GUI login at all. If it doesn't, the tailnet is unreachable after an
unattended reboot no matter how Ollama binds.

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

# 2. No `tailscale serve` — see below. If the earlier serve config is
#    still present, remove it so there is exactly one path in:
tailscale serve --https=11434 off

# 3. Something to benchmark
ollama pull qwen3.5:122b
```

## How to verify

```bash
# Service up, one owner, correct label
sudo launchctl print system/org.nixos.ollama | head -20
lsof -i :11434                      # exactly one listener

# Socket must be the 100.x tailscale address and NOTHING else
lsof -nP -i :11434        # => TCP 100.126.144.70:11434 (LISTEN)

# Must REFUSE on the LAN address
curl -s --max-time 5 http://192.168.1.198:11434/api/version   # must fail

# From another tailnet node
curl -s http://studio.jaguar-duckbill.ts.net:11434/api/version
curl -s http://studio.jaguar-duckbill.ts.net:11434/v1/models

# Models landed in the exclusion-covered path, not somewhere else
ollama list && ls ~/.ollama/models
```

**The real test** — not "is the process running":

```bash
sudo reboot
# then, WITHOUT logging in at the screen, from another machine:
curl -s http://studio.jaguar-duckbill.ts.net:11434/api/version   # tailnet still up?
ssh hodgesd@studio 'ollama run qwen3.5:122b "say hi"'
```

A generation completing with no session is what justifies the daemon
branch. If Metal is unreachable pre-login, fall back per the ordering in
the plan's CONTEXT (non-GUI user domain, then user agent + auto-login)
and say so plainly rather than shipping something fragile.

## How to disable

Comment out the `launchd.daemons.ollama` block and rebuild. There is no
serve config to retract. The CLI stays until `environment.systemPackages`
is also trimmed.

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
2. `lsof -nP -i :11434` shows `100.126.144.70` and nothing else; a curl
   against `192.168.1.198:11434` refuses. (Bind address *is* the access
   control — security rule 1.)
3. `kill` the process; it comes back within ~15s (KeepAlive + ThrottleInterval).
4. `ollama list` after a pull, and `ls ~/.ollama/models` is non-empty —
   proves `OLLAMA_MODELS` took and the models are inside the Phase 1
   exclusions.
5. Reboot without logging in, then generate over SSH. This is the one that
   decides whether the daemon branch was right.
