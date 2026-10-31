# PLAN — Phase 3 (studio: Ollama serving)

Scratch file for the current phase. Untracked; replaced each phase.

## Branch chosen: system LaunchDaemon (option 1)

FileVault is off, so the box boots to loginwindow unattended and a system
daemon starts with nobody logged in — which is the whole point of an
always-on inference server. `UserName = "hodgesd"` keeps models in `~`
(readable because the disk is never gated), so the Phase 1 Time
Machine/Spotlight exclusions still apply unchanged. No auto-login needed.

This is the plan's documented first preference. The Phase 2 observation
(is a GUI/user domain live post-reboot?) has **not** been made, but it
only matters if this branch fails — and the failure is concrete and
testable: a daemon that starts but cannot reach Metal. The acceptance
test below is specifically that, not "is the process running".

Fallbacks if it fails, in order: non-GUI `user` domain service, then
user agent + `system.defaults.loginwindow.autoLoginUser`.

## Verified before writing any config

- `unstablePkgs.ollama` on `aarch64-darwin` at our locked rev: **0.34.3**,
  not broken, `mainProgram = ollama`. Far past the 0.19 that introduced
  the MLX backend, so no brew fallback.
- nixpkgs exposes no MLX-vs-Metal build toggle to inspect from Linux;
  which runtime actually loads is a **runtime** fact. Hence the explicit
  "read the log and confirm the backend" step rather than a claim here.

## Intended changes — `hosts/darwin/studio/default.nix` only

1. `environment.systemPackages = [unstablePkgs.ollama]` so `ollama
   pull/ps/run` is on PATH, and the daemon uses the same store path.
2. `launchd.daemons.ollama`:
   - `ProgramArguments = [".../bin/ollama" "serve"]`, `UserName`, `RunAtLoad`,
     `KeepAlive`, `ThrottleInterval = 15`, `ProcessType = "Interactive"`.
   - `OLLAMA_HOST = "127.0.0.1:11434"` — loopback only, security rule 1.
   - **`HOME` and `OLLAMA_MODELS` set explicitly.** A LaunchDaemon does not
     inherit a usable `HOME` even with `UserName`; without this Ollama
     would pick a different models directory and silently sit outside the
     Phase 1 exclusions. This is the single most likely quiet bug here.
   - `OLLAMA_KEEP_ALIVE = "30m"`, `OLLAMA_MAX_LOADED_MODELS = "2"`.
   - Logs to `~/Library/Logs/ollama.log`.

## Not Nix — for me, after the switch

- `tailscale serve --bg --https=11434 http://127.0.0.1:11434` (one-time,
  persisted in tailscaled state, same as the mini's bridges).
- `ollama pull <model>` so there is something to benchmark.

## Acceptance (I run the first two; the agent verifies the rest over SSH)

1. `sudo darwin-rebuild switch --flake .#studio`
2. `sudo reboot`, then **do not log in** — generation must complete with
   no session. That is the real test.
3. Loopback-only: refuses on 192.168.1.198, answers via tailnet HTTPS.
4. One listener on :11434, owned by `org.nixos.ollama`.
5. MLX backend named in the log; tokens/s recorded as the Phase 3b baseline.
