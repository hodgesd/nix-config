# Claude Code Execution Prompt — Mac Studio "studio" AI Server

**How to use:** Paste the CONTEXT block plus exactly ONE phase block into
Claude Code per session, from the repo root. Phases 0–4 are sequential;
5–8 are independent add-ons gated on their own decisions. Review every
diff before applying — treat the output like a PR from a sharp new hire.

**Status legend:** update each phase header to `DONE <date> — see
docs/studio/phase-N.md` as it lands, mirroring docs/hermes/.

---

## CONTEXT BLOCK (include in every session)

```
You are adding my new Mac Studio M5 Ultra ("studio") to this nix-darwin +
NixOS flake repo as a dedicated local-AI inference server. Read this
entire context before acting.

ENVIRONMENT
- The fleet after this work: mbp/air (laptops), mini (M2 Pro — my daily
  desktop AND the Hermes Apple/vault bridges; primaryUse = "server"),
  studio (this machine — AI compute only), nixos-infra (NixOS VM on the
  HP mini's Proxmox — monitoring/control plane: Gatus, ntfy, Hermes,
  compose stacks).
- Division of duties is deliberate and must not drift in this work:
  nixos-infra WATCHES the Macs (never the reverse); the mini keeps the
  Apple-session bridges (vault-mcp/apple-mcp need my iCloud session —
  do NOT migrate them to studio); studio runs inference and heavy
  compute only. Put nothing on studio that something else depends on
  for monitoring or day-to-day use.
- All hosts are on one Tailscale tailnet. Internal HTTPS uses the
  existing patterns: `tailscale serve --bg` persisted in tailscaled
  state on Macs (see hosts/darwin/mini/default.nix comments), the
  sidecar module on nixos-infra. Reuse these; invent nothing.
- Serving stack decision (made): BOTH, in this order. Ollama first
  (Phase 3) because it is store-pinned and two lines — it proves the
  launchd + tailscale-serve + Gatus skeleton. Then oMLX (Phase 3b) as
  the engine the agent tooling actually points at, because it has an
  Anthropic-compatible /v1/messages endpoint and a paged SSD KV cache.
  Once oMLX is validated on real workloads, Ollama's launchd agent is
  disabled by one commented line and stays instantly revivable.
  Verified 2026-10-27 against our own flake.lock, do not re-derive:
    * unstablePkgs.ollama on aarch64-darwin is 0.34.3 — far past the
      0.19 that introduced the MLX backend. No brew fallback needed.
    * oMLX is NOT in nixpkgs (checked `omlx` and `python3Packages.omlx`
      at our locked unstable rev 7a0f122). Packaging it as a nix
      derivation is NOT a small job: it pins mlx==0.32.4 and takes
      mlx-lm, mlx-embeddings, mlx-vlm and mlx-audio from exact git
      commits. Do not attempt a nixpkgs-style derivation in these
      phases. Install it the way this repo already installs my-skhd,
      ical-buddy, mactop and opencode: a homebrew tap + brew, declared
      in homebrew.nix. The `brew trust` loop in that file already
      handles third-party taps.
- FileVault decision (REVISED 2026-10-30): **OFF on studio.** Earlier
  drafts of this plan assumed ON and built a whole pre-boot SSH-unlock
  recovery ladder around it; that is obsolete for this host and has
  been removed so nobody implements against it. Apple silicon still
  encrypts the internal SSD in hardware; FileVault adds password
  protection of the keys at rest. Accepted trade: weaker protection
  against physical access to the machine, in exchange for a box that
  boots all the way back unattended. Justified because it is
  physically secure, has no Apple ID, and holds no personal data —
  only re-downloadable model weights.
  Consequences that MUST drive implementation:
    * No pre-boot gate. A reboot or power cut returns to loginwindow on
      its own, and system LaunchDaemons start with nobody logged in.
    * User LaunchAgents still require a login session. So anything that
      must survive an unattended reboot is either a system LaunchDaemon
      or a user agent plus AUTO-LOGIN — and auto-login is available
      precisely because FileVault is off. This replaces the old "decided
      by the Phase 2 pre-boot test" rule; Phase 3 chooses on evidence.
    * The mini's posture is unchanged and still FileVault-on. Do not
      copy studio's choice there: that box holds an iCloud session.
  If FileVault is ever switched back on, the macOS 26+ SSH pre-boot
  unlock path becomes relevant again (password auth only, no Tailscale
  that early, LAN/jump-host required) — but write it down then rather
  than carrying dead guidance here.
- Model storage decision (made): internal SSD, default ~/.ollama.
  Models are re-downloadable — exclude from Time Machine and Spotlight,
  never back them up.
- Hardware facts, read off the machine 2026-10-30 (settled, do not
  re-derive): 96GB unified memory (hw.memsize 103079215104 = 98,304
  MB), 30 CPU cores (perflevel0 10 / perflevel1 20), 64 GPU cores, 2TB
  internal SSD, and `iogpu.wired_limit_mb` currently 0 — i.e. unset,
  running the implicit macOS default.
- macOS version: **27.2 (build 26B123)** — the Studio shipped newer
  than the 26.x this plan was drafted against. Consequences to carry
  into every phase:
    * "Start up when power is connected" (needs 26.5+) is available.
      The SSH FileVault unlock path (26+) is moot here — FileVault is
      off — but would be available if that ever changed.
    * `hosts/common/darwin/homebrew.nix` already handles macOS > 26:
      its activation script injects HOMEBREW_FAKE_MACOS=26.0 so `brew
      bundle` does not abort. That path WILL be exercised on first
      activation — expect it, and do not "fix" it.
    * nix-darwin 26.05 and the pinned brew predate macOS 27, so treat
      first-activation oddities as version skew before suspecting the
      studio config. CLAUDE.md already records one macOS 27 bug
      (calendr/remindd, 2026-09-16).
- Availability target: best-effort, not production. My $100/mo Claude
  subscription continues — local inference is a complement, never the
  only path. A studio outage is inconvenient, not critical. When a
  choice trades simplicity against another nine of availability, take
  simplicity and say so.

NON-NEGOTIABLE SECURITY RULES
1. Ollama's API has NO authentication and can pull/delete/run models,
   so its bind address IS the access control. **Nothing listens on the
   LAN or the internet — ever.** Two bind shapes satisfy that; both are
   acceptable, nothing else is:
     - loopback (127.0.0.1) fronted by `tailscale serve`, the mini's
       pattern, for services that tolerate a proxied Host header; or
     - the node's MagicDNS name, i.e. the tailscale interface alone.
   Ollama uses the second (REVISED 2026-10-30, superseding "127.0.0.1
   only, always"): it validates the HTTP Host header, `tailscale serve`
   forwards the original Host, and every proxied request therefore
   returned 403. Measured — a `Host: 127.0.0.1` override returned 200
   through the same proxy, OLLAMA_ORIGINS (including `*`) does not
   affect it, and serve has no Host-rewrite option. Verify the socket
   with `lsof -nP -i :11434`; it must show the 100.x tailscale address
   and nothing else. NEVER 0.0.0.0, never a LAN address. Phase 7
   (public access) is decision-gated and adds an authenticating proxy
   — never expose the bare API, not even "temporarily".
2. No secrets in the repo. sops-nix is the mechanism (see .sops.yaml);
   v1 needs no secrets at all — if you believe one is needed, stop and
   ask. Credentials a human must create → numbered checklist for me.
3. Everything you add must be declarative (Nix), commented with WHY at
   security- and reliability-relevant lines, and reversible — document
   the one-line disable for each service.
4. Respect existing gates: machine.primaryUse == "server" must keep
   excluding masApps, the t3-code cask, and agent-workbench-client on
   studio. If a change would re-include any of those, stop.

WORKING STYLE
- Plan first: open each phase by writing a short PLAN.md of intended
  changes; wait for my "go" before touching config.
- Small commits, imperative messages, one logical change each.
- Finish each phase by writing docs/studio/phase-N.md: what was built,
  how to verify, how to disable, and a 5-item manual test script.
- Formatting: `nix fmt` (alejandra). New files must be `git add`ed
  before `nix eval`/`build` can see them (flakes see tracked files only).
- Verification without the hardware: phases 0–1 and 4–6 must pass
  `nix eval --raw ".#darwinConfigurations.studio.system.drvPath"`
  (what CI runs). Phases needing the live machine say so explicitly.
- If anything is ambiguous, ask. Do not guess about my infra.
```

---

## PHASE 0 — Registry, flake output, CI (no hardware needed)

```
GOAL: studio exists as a buildable flake output and CI covers it, before
the machine is even unboxed. No services yet.

TASKS
1. lib/machines.nix: add
     studio = {
       type = "darwin";
       chip = "m5-ultra";
       formFactor = "desktop";
       primaryUse = "server";
     };
   Comment WHY primaryUse = "server": it reuses the three existing
   `primaryUse != "server"` gates (masApps, t3-code cask,
   agent-workbench-client); studio-specific behavior branches on
   machine.hostname == "studio" instead. Do not add new registry fields.
2. flake.nix: studio = libx.mkDarwin {hostname = "studio";}; in
   darwinConfigurations.
3. hosts/darwin/studio/default.nix: create with a header comment naming
   the machine's single purpose (AI inference server) and, for now, only
   the power block copied in spirit from the mini:
     power.restartAfterPowerFailure = true;
     power.restartAfterFreeze = true;
     power.sleep = { computer = "never"; display = 15; harddisk = "never"; };
   Include a recovery-posture comment (superseded 2026-10-30: FileVault
   is off, so it boots to loginwindow on its own; Gatus tells me).
4. CI: add studio to the eval matrix (.github/workflows/eval.yaml,
   attr darwinConfigurations.studio.system) and to the darwin build
   matrix in build.yaml.
5. README.md machines table: add the studio row (fill RAM/storage from
   me — ask, don't invent).

ACCEPTANCE
- nix eval --raw ".#darwinConfigurations.studio.system.drvPath" succeeds.
- git grep confirms studio appears in machines.nix, flake.nix, both CI
  matrices, README.
- Diff shows NO change to any other host's eval (spot-check mbp drvPath
  unchanged before/after).
- docs/studio/phase-0.md written.
```

---

## PHASE 1 — Headless-server baseline (no hardware needed)

```
GOAL: studio's host config makes it manageable with no keyboard attached
and immune to surprise reboots. Still no AI services.

TASKS
1. Remote management, declaratively in hosts/darwin/studio/default.nix:
   - Remote Login (SSH): nix-darwin has no first-class option on all
     releases — check what our pinned nix-darwin 26.05 offers
     (e.g. services.openssh / system.defaults / an activation script
     calling `systemsetup -setremotelogin on`). Use the most declarative
     mechanism available; if it needs one manual `systemsetup` run,
     write it into the Phase 2 bootstrap checklist instead of hacking
     around TCC. Remote Login is LOAD-BEARING on this host: it is how a
     headless, keyboard-less box is administered at all, and it carries
     the authorized key in hosts/darwin/studio/default.nix. (It was also
     the prerequisite for FileVault pre-boot unlock, which no longer
     applies now that FileVault is off.)
   - Power-on behavior: "Start up when power is connected" = Always
     (System Settings → Energy; macOS 26.5+, Mac Studio 2025+ — this
     machine qualifies). Strictly better than the old
     restart-after-power-failure: it also powers on from a full
     shutdown when power returns, giving a last-resort remote recovery
     (smart plug / breaker). Keep power.restartAfterPowerFailure too
     (harmless, nix-darwin-native, covers older semantics). The new
     setting is likely NOT exposed by nix-darwin 26.05 — check; if not,
     find its defaults domain or make it a Phase 2 checklist line. Add
     the power-failure startup delay (`systemsetup
     -setwaitforstartupafterpowerfailure 30`, multiples of 30s) so the
     router/switch and the Proxmox host come back before studio does.
   - Screen Sharing: same approach; manual checklist item is acceptable
     if there is no clean declarative path. Do not ship a fragile
     `defaults write` that fights MDM/TCC.
2. macOS update posture: via system.defaults (SoftwareUpdate /
   commerce domains as exposed by nix-darwin 26.05): automatic CHECK on,
   automatic INSTALL (OS updates and app auto-updates) off. Comment WHY:
   a self-installing OS update reboots the box mid-inference and, if the
   serving stack turns out to need a login session, leaves it not
   serving until someone logs in. Updates are a deliberate, scheduled
   act here.
3. GPU wired-memory ceiling: a launchd DAEMON (root; not a user agent)
   that runs at load:
     sysctl iogpu.wired_limit_mb=83500
   (85% of the confirmed 96GB = 98,304 MB, leaving ~14.5GB for the OS
   and the serving process). The live value reads 0, which means
   "unset — use the implicit default" rather than "no limit", so the
   gain over the ~65–75% default is real but bounded: roughly 9–20GB
   of extra model headroom. The sysctl does not persist across
   reboots, hence launchd. One-line disable: comment out the daemon,
   rebuild.
4. Backup/indexing hygiene for the future model/cache dirs,
   declaratively where possible. Cover BOTH engines' storage now so
   Phase 3b doesn't need a second mechanism: ~/.ollama (Ollama blobs)
   AND ~/.cache/huggingface (oMLX reads/downloads HF-format models).
   - The dirs will not exist yet at first activation: the exclusion
     step must `mkdir -p` each path first (tmutil addexclusion on a
     missing path fails or silently doesn't stick), then exclude.
     Idempotent, and structured so Phase 3b can add the oMLX SSD-cache
     dir as one more list entry.
   - Time Machine: tmutil addexclusion in an idempotent activation
     step or launchd once-per-boot — pick the simplest mechanism that
     survives rebuilds and comment the choice.
   - Spotlight: mdutil or a .metadata_never_index marker file created
     by the same step — research which actually works on current macOS
     and say so in the comment.

ACCEPTANCE
- Eval passes (same command as Phase 0).
- Every new block has a WHY comment and a documented one-line disable.
- Anything that could not be done declaratively is listed in
  docs/studio/phase-1.md under "manual bootstrap steps" for Phase 2 —
  nothing silently dropped.
```

---

## PHASE 2 — Hardware bootstrap (requires the machine; mostly ME, not Claude)

```
GOAL: the physical Studio runs this flake. Claude's job in this phase is
to produce the definitive ordered checklist in docs/studio/phase-2.md,
verifying each step against the repo's actual scripts — then I execute
it at the machine.

TASKS (the checklist to produce, verify, and refine)
1. macOS first-boot: create user "hodgesd" (registry default — confirm
   against lib/machines.nix; studio sets no username override), leave
   FileVault OFF (decided 2026-10-30 — see CONTEXT), and do NOT sign in
   to iCloud: no Apple ID on this box, it is not a bridges host.
2. Hostname: scripts/set_mac_name.sh or the three scutil --set commands,
   value "studio" — must match the flake attr exactly.
3. Install nix + bootstrap: follow scripts/bootstrap.sh (read it first;
   reflect what it ACTUALLY does in the checklist, including Rosetta if
   it installs it — nix-homebrew has enableRosetta = true).
   NIX FLAVOUR IS NOT OPTIONAL HERE. Since 2026-01-01 the Determinate
   installer defaults to *Determinate Nix*, whose daemon lives at
   /usr/local/bin/determinate-nixd. nix-darwin 26.05 checks for exactly
   that path and aborts activation (exit 2) unless `nix.enable = false`
   — verified by reading the generated activation script, not from
   docs. bootstrap.sh therefore passes `--prefer-upstream-nix` and
   fails fast if determinate-nixd exists anyway. Confirm the flag still
   exists (`... | sh -s -- install --help`) before the first run; if it
   was withdrawn, use `sh <(curl -L https://nixos.org/nix/install)
   --daemon` rather than quietly accepting Determinate, which would
   diverge studio from mbp/mini/air and silently drop the nix.settings
   in lib/helpers.nix.
4. First build: darwin-rebuild switch --flake .#studio from a clone of
   this repo. Expect the full cask download storm on first activation;
   note the known risk that one rotted vendor URL fails the whole
   bundle, and the recovery (retry; if a cask 404s persistently, we fix
   the shared list in a commit, not by hand-editing the machine).
5. Tailscale: log in via the app (cask is already in the shared list),
   confirm `tailscale status` works via the CLI shim, confirm MagicDNS
   name resolves from another tailnet node.
6. Manual steps carried over from Phase 1's doc (Remote Login / Screen
   Sharing toggles if they stayed manual; verify SSH from the mbp works
   over the tailnet).
7. Networking: Ethernet, not Wi-Fi (an inference server should not
   contend on the WLAN), plus a DHCP reservation so the LAN address is
   stable for break-glass access when the tailnet is unavailable.
   DONE 2026-10-30: en0, 192.168.1.198. Confirm the reservation exists
   on the router and record it in phase-2.md.
8. Smoke tests. FileVault is off, so there is no pre-boot unlock to
   exercise; what remains is "does it come back by itself, and does it
   SERVE by itself". Run these before trusting the box unattended:
   a. Plain `sudo reboot`. Without touching the keyboard, from another
      tailnet node: does SSH return on its own? Does studio rejoin the
      tailnet with nobody logged in? (If Tailscale needs a GUI session,
      remote admin after every reboot depends on the LAN path — find
      that out now, not during an outage.)
   b. THE DECIDING OBSERVATION for Phase 3, taken after (a) with NOBODY
      logged in at the screen. SSH in and run:
         launchctl print gui/$(id -u) >/dev/null 2>&1 \
           && echo "GUI domain live" || echo "no GUI session"
         launchctl print user/$(id -u) >/dev/null 2>&1 \
           && echo "user domain live" || echo "no user domain"
      - "no GUI session" means nix-darwin `launchd.user.agents` (the
        mini's pattern) will NOT serve after an unattended reboot. The
        answer is then either a system LaunchDaemon, or auto-login —
        which is an option here precisely because FileVault is off
        (`system.defaults.loginwindow.autoLoginUser`).
      - a live `user` domain without a GUI session is the middle
        branch: per-user service semantics, no root daemon, no
        auto-login. Check whether our pinned nix-darwin can declare
        one before proposing it.
      Record the output verbatim in phase-2.md; Phase 3 reads it.
   c. Log out of a GUI session afterwards and note whether user agents
      die (KeepAlive user agents stop at logout) — on a headless box
      that is how a Screen Sharing session ends, and it is a second way
      to lose the serving stack without a reboot.
   d. Power tests, gentle first (verify the config with `pmset -g`
      before either; `autorestartatconnect` should read 1 once the
      Energy setting is on — it read 0 on 2026-10-30):
      - graceful: `sudo shutdown -h now`, disconnect power, wait ~30s
        (the PSU needs to discharge), reconnect — "start up when power
        is connected" = Always should power it on with no button press.
      - only then the real outage: cut power at the outlet with the
        machine RUNNING (nothing important in flight, no update mid-
        install), restore after a minute — does it power on and climb
        the recovery ladder? An ordinary reboot exercises neither path.

ACCEPTANCE
- I can SSH to studio over the tailnet and run
  `darwin-rebuild switch --flake .` headless.
- `sysctl iogpu.wired_limit_mb` shows the Phase 1 value after a
  reboot (proves the daemon ran at boot).
- docs/studio/phase-2.md is the as-executed checklist with any surprises
  recorded.
```

---

## PHASE 3 — Ollama serving (requires the machine)

```
GOAL: Ollama serves models on loopback, reachable tailnet-wide over
HTTPS, surviving crashes and (attended) reboots.

TASKS
1. Package: unstablePkgs.ollama. FIRST verify our pinned
   nixpkgs-unstable's darwin ollama is recent enough for the MLX backend
   (>= 0.19 and MLX enabled in the darwin build — check the derivation,
   not just the version string). If it lags: add "ollama" to
   homebrew.nix's brews list gated however the repo would gate a
   host-specific brew (NB: brews are currently a single shared list —
   if gating is needed, ask me before restructuring), and leave a dated
   comment to revisit nixpkgs.
2. launchd USER agent "ollama" in hosts/darwin/studio/default.nix,
   modeled line-for-line on the mini's vault-mcp agent (RunAtLoad,
   KeepAlive, ThrottleInterval 15, ProcessType "Interactive" — carry
   over the App Nap comment; it throttles asyncio/stream flushing the
   same way), logs to ~/Library/Logs/ollama.log. Environment:
     OLLAMA_HOST = "127.0.0.1:11434";   # loopback ONLY — rule 1
     OLLAMA_KEEP_ALIVE = "30m";          # hot models stay resident
     OLLAMA_MAX_LOADED_MODELS = "2";
   Agent-vs-daemon is NOT a style choice — it decides whether this box
   serves after an unattended reboot. FileVault is off, so it boots to
   loginwindow by itself; the only question is what runs there. Pick
   from the Phase 2 (b) observation, in this order of preference:
     1. System LaunchDaemon with `UserName = "hodgesd"`. Serves with
        nobody logged in, needs no auto-login, and running as me it can
        still read OLLAMA_MODELS / the HF cache in ~ (the disk is not
        gated — that is the upside of FileVault being off). PREFERRED
        if it works. Relocate paths out of ~ only if testing shows a
        real permissions problem, and move the Phase 1 TM/Spotlight
        exclusions with them.
     2. Non-GUI `user` domain service, if Phase 2 (b) found that domain
        live and our pinned nix-darwin can declare one.
     3. `launchd.user.agents` (the mini's pattern) PLUS auto-login
        (`system.defaults.loginwindow.autoLoginUser`) — available only
        because FileVault is off. Last resort: it trades an
        always-unlocked desktop for simplicity, so take it only if 1
        and 2 fail.
   VERIFY, do not assume, that option 1 actually does Metal inference
   with no session — a daemon that starts but cannot reach the GPU is
   the specific failure to rule out. If it can't, fall back to 3 and
   say so plainly rather than shipping something fragile. State which
   branch you are on in PLAN.md and comment the WHY in the nix.
3. tailscale serve: one-time command (persisted in tailscaled state,
   same as the mini's bridges):
     tailscale serve --bg --https=11434 http://127.0.0.1:11434
   This is a CHECKLIST item for me, not Nix — but document it in the
   host file's header comment exactly like the mini does.
4. Verify end-to-end from another tailnet node:
     curl https://studio.<tailnet>.ts.net:11434/api/version
     curl .../v1/models   (OpenAI-compatible surface for future clients)
   and one real generation round-trip with a small model I pull by hand.
5. Confirm MLX engagement: pull one model ≥ a few GB, run a generation,
   and check ollama's log/`ollama ps` output for the MLX runner (the
   log names the backend). Record observed tokens/s in phase-3.md as
   the baseline.
6. Confirm the Phase 1 hygiene actually bit: ~/.ollama excluded from
   Time Machine (tmutil isexcluded) and not Spotlight-indexed.

ACCEPTANCE
- Service restarts after `kill` (KeepAlive) and after a plain
  `sudo reboot`.
- THE REAL TEST: after an unattended `sudo reboot` with NOBODY logged
  in at the screen, a generation completes end to end. A running
  process is not the test — Metal actually producing tokens with no
  session is. If the daemon branch cannot reach the GPU pre-login,
  fall back per the ordering above and document "serves after login"
  honestly rather than shipping a fragile daemon.
- API reachable tailnet-wide over HTTPS, NOT reachable on the LAN IP
  (verify with a curl against the machine's LAN address — must refuse).
- SINGLE OWNER: exactly one listener on :11434 (`lsof -i :11434`), and
  its launchd label is the Nix-declared one — no app login item, no
  brew-services unit, no second supervisor. Then change one env var in
  the Nix config, rebuild, and confirm the RUNNING process picked it
  up — proves the declarative config actually owns the service.
- One-line disable documented: comment out the launchd agent block,
  rebuild; plus `tailscale serve --https=11434 off` to retract the
  tailnet route.
- docs/studio/phase-3.md written, including the model-pull commands
  used and the tokens/s baseline.
```

---

## PHASE 3B — oMLX, the agent-facing engine (requires the machine)

> **SHELVED 2026-10-31 — do not execute this phase as written.** Ollama
> has its own MLX engine, selected per model by tag, *including* a
> 4-bit NVFP4 MoE, so the premise ("oMLX is how you get MLX, or how you
> get a quantized MoE on MLX") is wrong on both counts. Reopens only
> for a feature Ollama lacks — tiered SSD KV cache, Anthropic
> `/v1/messages` — and if it does, `mlx-lm` from nixpkgs is tried
> first because it is packaged and declarative. See ledger item **1b**.
> Everything below is retained for that day; the brew-tap instructions
> in particular are stale (the tap is
> `jundot/omlx https://github.com/jundot/omlx`, and the custom kernels
> need full Xcode).

```
GOAL: serve models through oMLX (omlx.ai, github.com/jundot/omlx,
Apache 2.0) so my agent tooling — Claude Code, T3 Code, OpenCode,
Codex, Hermes — can use the Studio, with long-context TTFT that makes
agent loops usable. Ollama from Phase 3 keeps running until this is
proven.

WHY THIS EXISTS (do not re-litigate, but DO verify each claim on my
hardware and record real numbers):
- Anthropic-compatible /v1/messages alongside OpenAI /v1/chat/
  completions. Ollama serves only the OpenAI shape, so Claude Code and
  T3 Code cannot point at it natively. This is the main reason.
- Paged SSD KV cache: cache blocks persist to disk in safetensors, hot
  blocks in RAM, cold evicted to SSD by LRU, so a re-sent long prefix
  restores in milliseconds instead of re-prefilling. Upstream claims
  agent TTFT 30-90s → under 5s. Agent loops re-send long prefixes
  constantly, which is exactly my workload.
- One process serves LLM + VLM + embedding + reranker models
  simultaneously with LRU eviction — if I ever do RAG over the Obsidian
  vault, that is the embedding and reranker side already running.
- It reads the standard HuggingFace cache and the LM Studio folder, so
  models I already have are visible with no re-download (the lm-studio
  cask is already in homebrew.nix).
- It has REAL API-key auth and refuses to start on a non-loopback
  address without a main API key. Ollama has none. This matters for
  Phase 7.

TASKS
1. Install declaratively through homebrew.nix:
     taps: "jundot/omlx" (the tap points at the repo itself; the
           formula lives at Formula/omlx.rb inside it)
     brews: "jundot/omlx/omlx"
   Mirror the existing third-party-tap entries (my-skhd is the prior
   art for a tap-qualified brew name). Comment WHY brew and not nix,
   citing the git-pinned MLX dependency set from the CONTEXT block —
   a future reader will otherwise assume laziness.
   NOTE: brews is currently ONE shared list across all darwin hosts,
   so this installs oMLX on the laptops too. Decide with me in PLAN.md:
   either accept that (it is a CLI, inert unless started) or do the
   per-role split first (Phase 6). Do NOT restructure the list
   unilaterally.
   Do NOT use --with-custom-kernel (it requires full Xcode).
2. launchd USER agent "omlx" in hosts/darwin/studio/default.nix,
   same shape as the Phase 3 ollama agent and the mini's bridges
   (RunAtLoad, KeepAlive, ThrottleInterval 15, ProcessType
   "Interactive" — carry the App Nap comment), logging to
   ~/Library/Logs/omlx.log.
   - Run the server directly (the brew-installed `omlx` binary, serve
     subcommand) under launchd. Do NOT use `omlx start` or `brew
     services`: those are competing supervisors and would fight
     launchd's KeepAlive. Read `omlx serve --help` on the machine and
     reflect the real flag names in the commit — the flags below are
     from docs, not from the binary.
   - Bind loopback only (`--host 127.0.0.1`), default port 8000.
     Confirm the port does not collide with anything on studio.
   - `--paged-ssd-cache-dir` pointed at a path on the internal SSD.
     Apply the SAME Time Machine and Spotlight exclusions as Phase 1
     did for ~/.ollama — this directory is pure regenerable cache and
     must never be backed up or indexed. If it is not under ~/.omlx,
     extend the Phase 1 exclusion step rather than writing a second
     mechanism.
   - `--max-concurrent-requests`: leave at the default 8 unless I ask.
   - Model dir: point at the HuggingFace cache so it shares models
     with anything else on the box.
3. tailscale serve for the tailnet route, same one-time pattern as
   Phase 3 (document in the host file header, it is not Nix):
     tailscale serve --bg --https=8000 http://127.0.0.1:8000
4. Verify from another tailnet node, and record results in the phase
   doc:
   - OpenAI shape: POST /v1/chat/completions round-trip.
   - Anthropic shape: POST /v1/messages round-trip.
   - Point Claude Code at it (ANTHROPIC_BASE_URL against the tailnet
     URL) and complete one real round-trip. This is the acceptance
     test that justifies the whole phase.
5. MEASURE, don't assume. Same model, same long prompt, three numbers
   in phase-3b.md: Ollama TTFT and tok/s (the Phase 3 baseline), oMLX
   cold TTFT, oMLX warm TTFT on a re-sent prefix. If the SSD cache
   does not deliver a clear win on MY workload, say so plainly in the
   doc — that result keeps Ollama primary and is a perfectly good
   outcome of this phase.
6. Decide with me, in writing, after the numbers: if oMLX wins, comment
   out the Phase 3 ollama launchd agent (one line, revivable) and
   retract its serve route; if not, leave Phase 3 primary and keep oMLX
   available but disabled. Do not make this call alone.

ACCEPTANCE
- Both endpoints answer over the tailnet; bare :8000 and :11434 refuse
  from the LAN address.
- SINGLE OWNER check as in Phase 3: one listener on :8000, launchd
  label is ours, and specifically NO `omlx start` supervisor or
  brew-services unit running alongside.
- Agent restarts after `kill` and after a plain `sudo reboot`.
- Claude Code completes a round-trip against studio.
- The three measurements are recorded, with an explicit
  keep-or-retire recommendation for Ollama.
- One-line disable documented for oMLX too (comment the agent,
  `tailscale serve --https=8000 off`).
- docs/studio/phase-3b.md written.
```

---

## PHASE 4 — Monitoring from nixos-infra (no studio hardware needed to write; needs it to verify)

```
GOAL: nixos-infra watches studio the same way it watches the mini.
Studio monitors nothing.

TASKS
1. hosts/nixos/nixos-infra/gatus.nix: add a "studio" group using the
   existing helpers:
   - icmp "studio" "studio" <tailnet name> — liveness (distinguishes
     "box down" from "ollama down").
   - http check against https://studio.<tailnet>.ts.net:11434/api/version
     — cheap, unauthenticated, no model load. Follow the existing
     helper's conditions; 60s interval like peers unless the file's
     conventions say otherwise.
   - If Phase 3b landed, add an equivalent http check for oMLX on
     :8000. Find its cheapest liveness route on the machine (a health
     or models-list endpoint) — it MUST NOT load or unload a model,
     and it must work with whatever auth posture Phase 3b left in
     place. Watch whichever engines are actually serving: a disabled
     engine must not leave a permanently-red check.
   - OPTIONAL, propose in PLAN.md: a low-frequency (~30m) real-inference
     probe — a tiny-model /v1/chat/completions with max_tokens=1 —
     because /api/version proves the process answers, not that
     inference works (four distinct health states: box up, SSH up, API
     answering, inference producing tokens). Weigh the cost: it loads a
     model and holds RAM per OLLAMA_KEEP_ALIVE. If skipped, say so in
     the phase doc rather than implying inference is monitored.
2. Alerts: inherit the file's existing ntfy alerting (gatus topic) —
   zero new alerting infrastructure.
3. Deploy: just deploy-check, then just deploy. Confirm both endpoints
   green on https://status.<tailnet>.ts.net and that stopping the
   ollama agent on studio flips exactly the http check (icmp stays
   green), with an ntfy alert and a recovery notice. NB: the agent has
   KeepAlive, so `kill` restarts it in seconds — stop it for real with
   `launchctl bootout gui/$(id -u)/<label>` and document that as the
   maintenance-stop command in the phase doc.

ACCEPTANCE
- Both checks visible and green in Gatus UI; the kill-test above
  behaves as described.
- docs/studio/phase-4.md written (what's watched, what each alert
  means, how to silence during maintenance).
```

---

## PHASE 5 — Remote Nix builder (optional; DECIDED: yes)

```
GOAL: mbp and air offload aarch64-darwin builds to studio over
Tailscale SSH. Studio needs nothing new beyond an authorized key and
trusted-user wiring; the CLIENTS get the config.

TASKS
1. Studio side: ensure the build user (hodgesd) is in nix
   trusted-users (helpers.nix already does this fleet-wide — verify,
   don't duplicate) and SSH from the laptops works non-interactively
   over the tailnet. GOTCHA to design around, not discover: remote
   builds are performed by the CLIENT's nix-daemon, which runs as
   root — so it is root's SSH identity/known_hosts on mbp/air that
   must reach studio, not mine. Decide key placement + sshUser/sshKey
   in buildMachines explicitly (checklist item for me if a new key is
   needed; prefer my existing LAN key pattern from nixos-common.nix as
   prior art for where keys live).
2. Client side: a small shared darwin module (e.g.
   hosts/common/darwin/remote-builder.nix) gated
   machine.hostname != "studio" && machine.type == "darwin" — or an
   explicit hostname allowlist (mbp, air, mini?) — setting:
     nix.distributedBuilds = true;
     nix.buildMachines = [{
       hostName = "studio";   # tailnet MagicDNS
       system = "aarch64-darwin";
       maxJobs / speedFactor sized to the Ultra (ask me for core count);
       supportedFeatures = ["big-parallel"];
     }];
   Comment the failure mode: if studio is unreachable, nix falls back
   to local builds — slow but never broken. Verify that claim on the
   pinned nix version and say in the comment whether it needs
   builders-use-substitutes / a fallback flag to be true.
3. GC: note in the phase doc that studio joins the `just gc` cadence;
   if the justfile's gc recipe is per-host-local, add a line to the doc
   (not automation) for running it on studio over SSH.

ACCEPTANCE
- From mbp: a `nix build` of something uncached shows "building on
  'ssh://studio'" in the log and succeeds.
- With studio's tailscale down, the same build still succeeds locally.
- One-line disable: remove the module import / set
  nix.distributedBuilds = false. docs/studio/phase-5.md written.
```

---

## PHASE 6 — Cask role split (optional; DECISION PENDING — do not start without my go)

```
GOAL: end the 2026-08-19 "everyone gets the full workstation cask list"
collapse: servers (mini, studio) get a deliberate short list, so ~45
third-party download URLs stop being activation risks on headless boxes.

TASKS
1. In homebrew.nix, split casks into: core (every darwin host —
   orbstack, tailscale-app [lives in tailscale.nix — leave it there],
   karabiner-elements?, swiftbar?, ghostty — PROPOSE the exact sets in
   PLAN.md, reasoning per entry, before editing) and workstation-only
   (++ lib.optionals (machine.primaryUse != "server") [...]).
2. CRITICAL: onActivation.cleanup = "uninstall" means every cask that
   leaves a server's list is REMOVED from the mini on its next
   activation. The PLAN.md must list exactly what the mini will lose,
   and I approve that list explicitly. Check the mini's host dir and
   docs for apps its bridges/monitoring rely on before proposing.
3. Studio inherits the server list automatically (primaryUse gate).

ACCEPTANCE
- Eval passes for all six hosts (mbp, mini, air, studio, nixos-infra,
  t3-code); mbp/air cask set is byte-identical to before (diff the
  brewfiles or the drvs).
- docs/studio/phase-6.md records the final per-role lists and the
  mini-removal list as approved.
```

---

## PHASE 7 — Authenticated access from outside the tailnet (DEFERRED; decision-gated, do not start without my explicit go)

```
GOAL: reach the Studio's models from networks where the Tailscale
client is blocked (work), without ever exposing the unauthenticated
Ollama API.

PRECONDITION (mine, not Claude's): I have confirmed this doesn't cross
my employer's acceptable-use line. If I haven't said so in the session,
stop.

DESIGN (agreed direction — validate details against current docs at
execution time). WHICH ENGINE IS PRIMARY CHANGES THIS PHASE:

IF oMLX is primary (Phase 3b won): it has native main-API-key auth and
refuses to start on a non-loopback address without one, so NO separate
proxy is needed — that is a real simplification, take it.
1. sops-nix secret on studio for the oMLX main API key. This is the
   first secret on this host: add studio's age recipient to .sops.yaml
   per docs/ADDING_MACHINE.md step 5 and create secrets/studio.yaml.
   The launchd agent reads it the way the mini's bridges read theirs
   (cat the sops path into an env var inside the script — see
   hosts/darwin/mini/default.nix). NB our sops on darwin is the
   SYSTEM-level sops-nix darwin module (secrets materialize at
   activation / via its boot-time mechanism), NOT Home Manager's
   login-time agent — but VERIFY, don't assume: after a reboot +
   remote unlock with NO GUI login, confirm the secret path exists and
   is readable by the service user BEFORE the serving process needs
   it. A server that starts pre-login but can't read its key is a
   silent 401 generator.
2. Keep the bind on loopback and let Tailscale Funnel expose it; do NOT
   bind 0.0.0.0. Confirm oMLX still enforces the key on a loopback bind
   fronted by Funnel — if "allow inference without API key" defaults on
   for loopback, turn it OFF explicitly and comment why.

IF Ollama is primary (oMLX retired): Ollama has no auth at all, so a
proxy is mandatory.
1. Tailscale Funnel fronting NOT ollama but a thin authenticating proxy
   (Caddy or equivalent from nixpkgs) as a launchd agent: listens
   127.0.0.1:<port>, requires a static bearer token (sops-nix secret as
   above), forwards to 127.0.0.1:11434.

EITHER WAY:
2. Funnel exposes ONLY the authenticated port. CONSTRAINT: Funnel
   (unlike plain serve, which the mini uses on arbitrary ports) only
   accepts ports 443, 8443 and 10000 — verify against the tailscale
   version on the machine. The public URL will be on one of those,
   proxying to the authenticated loopback port; pick one not already
   claimed by a serve config on studio. The Phase 3/3b serve configs
   (tailnet-internal) remain separate and unchanged.
3. Rate-limit and log at the authenticated edge (requests land in a
   logfile I can tail; no bodies logged).
4. Alternative to propose in PLAN.md with one paragraph of trade-offs:
   Open WebUI (login page as the only public surface) behind the Funnel
   instead of raw API+token — pick based on whether I said I want chat
   or API access from work.

ACCEPTANCE
- From a non-tailnet network: requests without the token are rejected
  (401), with it they reach /v1. From the tailnet: Phase 3 path
  unchanged.
- Bare 11434 is still unreachable from anywhere but localhost.
- One-line disable: `tailscale funnel ... off` + comment out the proxy
  agent. docs/studio/phase-7.md includes the credential inventory
  (token name/location, NOT value) and rotation procedure.
```

---

## PHASE 8 — Hermes uses the local model (optional)

```
GOAL: hermes-agent on nixos-infra can route requests to studio's
OpenAI-compatible endpoint, making local inference available to my
agent surface (Telegram) with no new credentials leaving the tailnet.

TASKS
1. READ docs/hermes/phase-local-model.md FIRST — local-model work for
   Hermes already has a phase doc. Reconcile: this phase implements or
   updates that plan with studio as the endpoint; do not fork a second
   design. If they conflict, present the conflict, don't choose.
2. Point Hermes at the primary engine's OpenAI-compatible base URL
   (ollama :11434/v1, or oMLX :8000/v1 if Phase 3b won) per its
   current version's provider-config syntax (read the hermes-agent docs
   for the deployed version — see docs/hermes/runtime.md). API key:
   whatever placeholder its OpenAI-compatible provider requires; no
   real secret exists for the tailnet path.
3. Honest degradation: if studio is down/unlocked-pending, Hermes must
   fail that provider cleanly (error or fallback per its config), not
   hang. Verify by testing with the ollama agent stopped.
4. Respect ALL standing hermes security rules from docs/hermes/ — this
   phase adds a provider, not tools.

ACCEPTANCE
- A Telegram round-trip answered by a local model (verify via the
  primary engine's log on studio showing the request — ollama log +
  `ollama ps`, or ~/Library/Logs/omlx.log).
- With studio down, Hermes degrades per its config and recovers when
  studio returns.
- docs/studio/phase-8.md cross-references the hermes docs it touched.
```

---

## Open decisions ledger

| # | Decision | Status |
|---|----------|--------|
| 1 | Serving stack: Ollama (MLX backend, nixpkgs 0.34.3) as the proven baseline | **Decided** |
| 1b | oMLX / `mlx-lm` as a second engine | **Decided 2026-10-31: NO — one server, no model-coverage gap.** Ollama runs its own MLX engine, selected per model by tag, and the library includes a **4-bit (NVFP4) MLX MoE** — `qwen3.6:35b-a3b-nvfp4`, 21.5 GiB, `Qwen3_5MoeForConditionalGeneration`, 256 experts / 8 active. An earlier draft claimed that gap existed and made it the trigger for this item; it was wrong (see phase-3.md). Reopen only for a *feature* Ollama lacks — tiered SSD KV cache, Anthropic `/v1/messages` — never for model access. If it ever reopens, `mlx-lm` outranks oMLX: `python3Packages.mlx-lm` 0.31.3 is in nixpkgs for aarch64-darwin and not broken, whereas oMLX is in neither nixpkgs nor PyPI and needs **full Xcode** for its Metal custom kernels (CLT alone → `xcrun: unable to find utility "metal"`), with silent slow fallbacks otherwise. |
| 1c | ~~oMLX in the shared `brews` list installs it on laptops too~~ | **Moot** — no brew install happening (see 1b) |
| 1d | Model assignment: **`qwen3.6:35b-a3b`** (GGUF MoE) for Hermes/tool calling, **`qwen3.8:27b`** (GGUF dense) for code review/reasoning/vision. 37.6 GiB resident together, both hot under `OLLAMA_MAX_LOADED_MODELS = 2`. GGUF because of 1e, not by preference — the MLX tags are `…-a3b-nvfp4` / `…27b-mlx` and nothing else changes if 1e flips. Identify models by **manifest digest + `config.json`**, never by tag name — several tags alias one manifest (`35b-mlx` ≡ `35b-a3b-nvfp4`; `35b` ≡ `35b-a3b`). | **Decided 2026-10-31** |
| 1e | **MLX requires leaving nixpkgs. Open.** Measured on studio 2026-10-31: `ollama pull …-nvfp4` → `this model requires MLX support, but the MLX runtime is not available`; the closure ships only `llama-server`/`llama-quantize`, no `.dylib`, no `.metallib`, while the binary `dlopen`s the runtime (`failed to load MLX dynamic library`). And `nixpkgs#python3Packages.mlx` reports `Device(cpu, 0)` — CPU-only. Cause: MLX's Metal kernels need Apple's `metal` compiler (full Xcode only), unavailable to a nix build; the same limit oMLX's README documents. So MLX needs an Apple-built binary — Ollama DMG/Homebrew, PyPI `mlx` wheel, or oMLX DMG — each giving up the nixpkgs-managed launchd daemon. **RESOLVED 2026-10-31: neither.** The runtime is `dlopen`ed, so it was a missing file, not a wrong build — `fetchurl` upstream's `ollama-darwin.tgz` for the same version (hash verified against its published `sha256sum.txt`) and rebuild the tree with `mlx_metal_v3`/`v4` in `lib/ollama`. One nix-managed daemon, no Homebrew, no Xcode, no login session. Verified end to end on studio: `mlx runner is ready`, `/api/generate` → 117 tokens at 159.4 tok/s, TTFT 299ms, 100% GPU. Note `OLLAMA_LIBRARY_PATH` is not read by 0.34.3, and the binary must be **copied** not symlinked (Go resolves its own path). Rejected alternative, for the record: Ollama via the repo's existing declarative `homebrew.nix` (keeps one server, one API), cost being a third-party download in the activation path and a conflict with the nix daemon to resolve. Unverified whether brew's ollama ships the runtime — check for a `.metallib`/MLX dylib before committing to it. | Pending — needs a go |
| 2 | FileVault **OFF** on studio (revised 2026-10-30): physically secure, no Apple ID, no personal data, and availability is the point. Hardware encryption still applies. Mini stays FileVault-on. | **Decided: off** |
| 3 | Model storage: internal SSD, `~/.ollama` | **Decided** |
| 4 | Remote builder (Phase 5) | **Decided: yes** |
| 5 | Cask role split (Phase 6) | Pending — needs mini-removal list approval |
| 6 | Public access (Phase 7) + chat-vs-API shape | Deferred — needs workplace-policy check + explicit go |
| 7 | Studio hardware: **96GB / 30 CPU / 64 GPU / 2TB, macOS 27.2** — sysctl N = 83,500; Phase 5 maxJobs sized off 30 cores | **Resolved 2026-10-30** |
| 8 | UPS for studio + network gear + Proxmox host (graceful-shutdown signaling; macOS supports UPS shutdown policies in Energy settings) | Pending — hardware purchase, my call; plan assumes none until then |
| 9 | **Nix flavour / installer.** The whole fleet runs **upstream Nix**, and `nix.enable` stays `true` so `lib/helpers.nix` keeps managing `trusted-users` and `experimental-features` declaratively. `scripts/bootstrap.sh` pins this with `--prefer-upstream-nix` and aborts if `/usr/local/bin/determinate-nixd` exists. | **Decided: upstream, fleet-wide** — but see the standing liability below |

### Standing liability — item 9 (review on trigger, not on a schedule)

Determinate's installer calls upstream Nix "not a supported configuration"
and says the `--prefer-upstream-nix` flag "may be removed in a future
release". Verified present in installer **v3.24.1** on 2026-10-30 by
reading the binary's own `install --help`, alongside `--determinate`
(env equivalents: `NIX_INSTALLER_PREFER_UPSTREAM_NIX`,
`NIX_INSTALLER_DETERMINATE`). The shell wrapper at
install.determinate.systems/nix injects neither flag — it passes
arguments straight through.

**Why this is a tracked decision and not a preference.** nix-darwin 26.05
aborts activation outright (`exit 2`, "Determinate detected") when
`determinate-nixd` is present and `nix.enable` is true. The documented
alternative, `nix.enable = false`, hands Nix management to Determinate and
takes the `nix.*` options with it — `lib/helpers.nix`'s `nix.settings`
would have to move to `/etc/nix/nix.custom.conf`, i.e. out of this flake.
That is a real loss of declarativeness and must be an all-four-Macs
migration, never a per-host accident.

**Triggers to revisit** (not a date):
1. `--prefer-upstream-nix` disappears or stops working — bootstrap.sh's
   guard turns this into a loud, early failure rather than a broken Mac.
2. Building any Mac from scratch — cheapest moment to change install path.
3. A deliberate decision to adopt Determinate fleet-wide.

**If trigger 1 or 2 fires**, the drop-in replacement is upstream's own
installer, already noted in `scripts/bootstrap.sh`:
`sh <(curl -L https://nixos.org/nix/install) --daemon`. The end state is
identical — upstream Nix, multi-user daemon — so switching costs no config
change. Only the install path differs; the DetSys installer is kept for now
because its macOS handling (APFS volume, real uninstaller, idempotent
re-runs) is still better.

**Not verified, and it does not matter:** which flavour the installer picks
when *neither* flag is passed. The docs say Determinate; the binary's
`--determinate` flag reads like opt-in; `plan` needs root, so it was not
settled empirically. The pin is correct either way — essential if the
default is Determinate, a no-op documenting intent if it is not — and the
guard catches any mismatch. Do not spend time resolving this.
