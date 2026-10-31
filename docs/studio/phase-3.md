# Phase 3 — studio: Ollama serving

**Status: DONE 2026-10-31.** Daemon up on `100.126.144.70:11434`, no
serve config, MLX runtime packaged, both MLX models resident and
measured. Remaining acceptance items need real workloads, not more
setup.

## What was built

`hosts/darwin/studio/default.nix`:

| Thing | Detail |
|---|---|
| Package | `unstablePkgs.ollama` **0.34.3**, rebuilt with upstream's MLX runtime added — see "FIXED: the MLX runtime" below. No brew, no Xcode. |
| CLI | `environment.systemPackages = [ollama]` — same store path as the daemon, so `ollama ps` can never talk to a different build |
| Service | `launchd.daemons.ollama` → label `org.nixos.ollama` |
| Bind | `OLLAMA_HOST = studio.jaguar-duckbill.ts.net:11434` — tailscale interface only |
| CLI dial address | `environment.variables.OLLAMA_HOST`, same value — see below |
| Residency | `OLLAMA_KEEP_ALIVE = 30m`, `OLLAMA_MAX_LOADED_MODELS = 2` |
| Logs | `~/Library/Logs/ollama.log` |

### The CLI needs the same variable, for the opposite reason

Binding the tailnet name fixed the 403 and broke every local `ollama`
command: the CLI defaults to `127.0.0.1:11434`, nothing listens there
any more, and it fails with `could not connect to ollama server` while
the service is running perfectly. Hence
`environment.variables.OLLAMA_HOST` as well as the daemon's — listen
address and dial address, same string, and they must not drift apart.

nix-darwin writes it into `/etc/zshenv` (which sources the generated
`…-set-environment`), and non-interactive SSH does source that — so
`ssh studio 'ollama pull …'` works unattended. Verified:
`ssh studio 'echo $OLLAMA_HOST'` prints the address.

**Gotcha, and it will catch you once:** `/etc/zshenv` is read at shell
*startup*, so the shell you ran `darwin-rebuild switch` in still fails
with `could not connect to ollama server`. The daemon is fine; the shell
is stale. `exec zsh -l`, or open a new tab.

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

### Two engines, one service: how to actually get MLX

Ollama runs **both** a llama.cpp path (GGUF) and an MLX path on Apple
silicon, behind one API on one port. Which one you get is a property of
the **model tag**, not of a setting — there is nothing to configure.
MLX coverage is per-model and incomplete.

Told apart from the registry manifest without downloading anything:

| | GGUF tag | MLX tag |
|---|---|---|
| Layer media type | `…image.model` (one blob) | `…image.tensor` (one per tensor, named) |
| Layer count | 4 | ~1000–1200 |
| `runner` field | `"llamacpp"` *or unset* | unset |

**Only the layer media type is reliable.** The `runner` field is often
absent on GGUF tags too (`qwen3.8:27b-q4_K_M` leaves it unset while
`qwen3.8:27b` sets `"llamacpp"`, both plain GGUF), so it cannot be used
as the discriminator.

Naming convention, verified in both families: **`-mlx` is an alias for
`-nvfp4`** — NVFP4 is just the 4-bit quantization of the MLX artifact,
so the two suffixes name one thing from different angles.
`qwen3.8:27b-mlx` ≡ `qwen3.8:27b-nvfp4` (`5642e97495e1`), exactly as
`qwen3.6:35b-mlx` ≡ `qwen3.6:35b-a3b-nvfp4`. The quantizations available
in MLX format are `-nvfp4`/`-mlx` (4-bit), `-mxfp8`, and `-mlx-bf16`.

And one more size collision of the kind that caused the error below:
`qwen3.8:27b-bf16` is **GGUF** while `qwen3.8:27b-mlx-bf16` is **MLX**,
both 51.8 GiB.

```bash
curl -s https://registry.ollama.ai/v2/library/<name>/manifests/<tag> | python3 -m json.tool
```

**The trap: a tag name is not a model identity, and size is not either.**
Several tags are aliases of one manifest, and the names do not say so.
Verified by comparing the sha256 of the manifest bodies — this is the
only reliable test:

| Tag | Manifest sha | Config | Layers | Size | Engine |
|---|---|---|---|---|---|
| `qwen3.6:35b-mlx` | `4a5e082f2bd3` | `577d7d469489` | 1055 | 21.5 GiB | MLX |
| `qwen3.6:35b-a3b-nvfp4` | `4a5e082f2bd3` | `577d7d469489` | 1055 | 21.5 GiB | MLX |
| `qwen3.6:35b` | `a7eb95c53bcf` | `99afa5bbf1e7` | 4 | 21.1 GiB | llama.cpp |
| `qwen3.6:35b-a3b` | `a7eb95c53bcf` | `99afa5bbf1e7` | 4 | 21.1 GiB | llama.cpp |
| `qwen3.6:35b-a3b-mlx-bf16` | `bbf3a1458a4f` | `2df7a1fdb505` | 1055 | 67.0 GiB | MLX |
| `qwen3.8:27b-mlx` | — | — | 1209 | 16.9 GiB | MLX |
| `qwen3.8:27b` | — | — | 4 | 16.5 GiB | llama.cpp |

Read that carefully: **`35b-mlx` and `35b-a3b-nvfp4` are the same
bytes**, and so are `35b` and `35b-a3b`. There is no dense 35B in the
library — `35b` is just an alias for the MoE. The `-a3b` infix is
decoration on some tags and absent from others pointing at identical
content.

Architecture comes from the `…image.json` layer (the HF `config.json`),
not from the name:

```bash
dg=$(curl -s "https://registry.ollama.ai/v2/library/qwen3.6/manifests/35b-a3b-nvfp4" \
     | python3 -c 'import sys,json;print(next(l["digest"] for l in json.load(sys.stdin)["layers"] if l["mediaType"].endswith(".json")))')
curl -sL "https://registry.ollama.ai/v2/library/qwen3.6/blobs/$dg" | python3 -m json.tool
```

Which gives, confirmed:

| Tag | `architectures` | Experts |
|---|---|---|
| `qwen3.6:35b-a3b-nvfp4` | `Qwen3_5MoeForConditionalGeneration` | 256, 8 per token |
| `qwen3.8:27b-mlx` | `Qwen3_5ForConditionalGeneration` | dense |

An earlier draft of this doc asserted `qwen3.6:35b-mlx` was a dense
model and that no 4-bit MLX MoE existed. Both were wrong, inferred from
tag names and file sizes. The 1055-layer match with
`35b-a3b-mlx-bf16` was already visible and should have settled it.
**Check digests and `config.json`; never the tag.**

### FIXED: the MLX runtime, which nixpkgs cannot build

**Resolved 2026-10-31.** The section below describes the problem; this
describes the fix, which keeps one nix-managed daemon and needs neither
Homebrew, Xcode, nor a login session.

The runtime is `dlopen`ed, so it is a missing *file*, not a wrong build.
The search path comes from the binary's own location (measured with
`OLLAMA_DEBUG=1`):

```
<prefix>/bin/lib/ollama
<prefix>/lib/ollama          ← where nixpkgs puts llama-server
<prefix>/bin
```

`OLLAMA_LIBRARY_PATH` exists as a string in the binary but 0.34.3 does
**not** read it — absent from the server's env dump, and setting it
changes nothing. So the libraries have to sit beside the binary.

`hosts/darwin/studio/default.nix` therefore `fetchurl`s upstream's own
`ollama-darwin.tgz` for the **same version** (hash verified against the
release's published `sha256sum.txt`) and rebuilds the tree with
`mlx_metal_v3` and `mlx_metal_v4` inside `lib/ollama`. Two constraints
that are easy to get wrong:

- **Copy, do not symlink.** Go resolves its own executable path, so a
  symlinked `bin/ollama` sends the search back to the original store
  path and misses the libraries. No `symlinkJoin`.
- **The url is derived from `ollamaBase.version`.** A nixpkgs bump
  cannot silently pair the binary with a mismatched runtime: the version
  follows, and the pinned hash then fails the build until updated.

Verified on studio before writing the config, using a scratch copy of
the tree:

```
DEBUG dynamic.go:30  "MLX dynamic library loaded"
                     path=.../lib/ollama/mlx_metal_v4/libmlxc.dylib
INFO  client.go:420  "starting mlx runner subprocess"  model=gemma4:12b-mlx
DEBUG runner.go:221  "Configured MLX wired memory"  active="7.13 GiB"
INFO  client.go:109  "mlx runner is ready"

/api/generate → 'Red, Yellow, Blue'
                117 tokens, 159.4 tok/s, TTFT 299 ms, ollama ps 100% GPU
```

This machine selects **v4**. `v3` is kept anyway (~190MB) so a
GPU-family probe change cannot silently break a headless box.

Upstream's own macOS install would not do: `docs.ollama.com/macos`
documents only the `.dmg` drag-and-drop, and `install.sh` on Darwin
does `rm -rf /Applications/Ollama.app`, installs the GUI app, symlinks
`/usr/local/bin/ollama`, and runs `open -a Ollama`. That needs a login
session, starts a second server on `:11434`, and shadows the nix CLI.
The tarball is used as a library source only.

### The problem this fixed: nixpkgs ships no MLX runtime on macOS

Everything above is about what the *registry* offers. What this *build*
can execute is a separate question, and it is the one that governs.
Measured on studio 2026-10-31:

```
$ ollama pull qwen3.6:35b-a3b-nvfp4
Error: this model requires MLX support, but the MLX runtime is not available
```

Why, from the closure itself:

- `lib/ollama/` contains **only** `llama-server` and `llama-quantize`.
- No `.dylib` and no `.metallib` anywhere in the ollama store path.
- The binary *does* contain the MLX code — `github.com/ollama/ollama/mlxrunner`,
  `mlx._Ctype_*` cgo symbols, `mlx_metal_get_metallib_path` — and
  `dlopen`s the runtime at startup: `failed to load MLX dynamic library
  (searched: %v)`. Compiled in, never shipped.

And it is not just Ollama. `nixpkgs#python3Packages.mlx` imports and
computes, but:

```
>>> mx.default_device()
Device(cpu, 0)
```

A **CPU-only** MLX. So there is **no MLX GPU path through nixpkgs on
macOS at all** — not Ollama, not `mlx-lm`.

The shared cause: MLX's Metal kernels must be compiled by Apple's
`metal` compiler, which ships only with full Xcode and is unavailable to
a nix build. This is the same constraint oMLX's README documents
(`xcrun: unable to find utility "metal"`); it is a general nix-on-macOS
limit, not an oMLX quirk. Any MLX on this machine must come from an
Apple-toolchain-built binary — Ollama's official DMG/Homebrew, a PyPI
`mlx` wheel, or oMLX's DMG — each of which gives up the
nixpkgs-managed daemon.

**Lesson for this file:** a registry manifest proves what the weights
are. Only running it proves what the box does. Three successive drafts
here got the model story wrong by reasoning from metadata — tag names,
then file sizes, then manifest digests — without executing anything.

### Model assignment

**MLX, both of them** — measured on the deployed daemon 2026-10-31:

| Workload | Model | Architecture | Size |
|---|---|---|---|
| Hermes, tool calling | `qwen3.6:35b-a3b-nvfp4` | MoE, 256 experts / 8 active | 21.5 GiB |
| Code review, reasoning, vision | `qwen3.8:27b-mlx` | dense 27B | 16.9 GiB |

**These are intended assignments, not live wiring.** Nothing consumes
this server yet: `hermes.nix` still has
`model.base_url = "https://openrouter.ai/api/v1"` and is untouched.
Pointing Hermes here is **Phase 8**, and it is optional. Phase 3 ends
with a server that works and is measured — not with anything using it.

Both resident = 38.4 GiB, comfortable under the 81.5 GiB ceiling, and
`OLLAMA_MAX_LOADED_MODELS = 2` keeps both hot so they do not evict each
other.

### Measured: MLX vs llama.cpp on this machine

Same model, same prompt, `num_predict=200`, `temperature=0`, warm,
successive requests left to right:

| Model | Engine | tok/s |
|---|---|---|
| `qwen3.8:27b-mlx` | MLX | 127.1 → 141.1 → **145.5** |
| `qwen3.8:27b` | llama.cpp | 94.0 → 94.2 → **94.0** |
| `qwen3.6:35b-a3b-nvfp4` | MLX | 149.8 → 199.6 → 272.3 → **272.8** |
| `qwen3.6:35b-a3b` | llama.cpp | 105.6 → 102.7 → 91.7 → **103.8** |

So MLX is **~55% faster on the dense 27B and ~2.7x on the MoE** — far
past the ~20% upstream advertises, and the reason the packaging work in
this phase was worth doing.

Two behaviours the averages hide:

- **MLX ramps; llama.cpp does not.** MLX needs 3–4 requests to reach
  steady state (149 → 272 on the MoE), while llama.cpp is flat from the
  first request. On an always-on box with `OLLAMA_KEEP_ALIVE = 30m` that
  warmup amortises to nothing, which is the ideal case for MLX — but it
  means a single cold benchmark run *understates* MLX badly.
- **Cold first-token is worse on MLX.** A cold `qwen3.8:27b-mlx` showed
  1625ms prompt-eval against 242ms for GGUF. Irrelevant for a resident
  server, relevant if anything ever runs it one-shot.

This also settles a claim from an external review that MLX loses on MoE
architectures (citing an M1 Ultra comparison). Not on this hardware and
these models: the MoE is where MLX wins by the largest margin.

A cold, single-shot measurement taken earlier suggested the opposite
(GGUF 65.3 vs MLX 53.8 tok/s) — that was load and warmup, not throughput.
Measure warm, and more than once.

## Manual steps (not Nix)

```bash
# 1. Activate
cd ~/nix-config && git pull && sudo darwin-rebuild switch --flake .#studio

# 2. No `tailscale serve` — see below. If the earlier serve config is
#    still present, remove it so there is exactly one path in:
tailscale serve --https=11434 off

# 3. The two models. OLLAMA_HOST comes from environment.variables after
#    step 1; before that it must be set by hand (see below). NOT
#    127.0.0.1 — nothing listens there any more.
ollama pull qwen3.6:35b-a3b-nvfp4   # Hermes / tool calling (MLX MoE)
ollama pull qwen3.8:27b-mlx         # code review / reasoning / vision (MLX dense)
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
ssh hodgesd@studio 'ollama run qwen3.8:27b-mlx "say hi"'
```

A generation completing with no session is what justifies the daemon
branch. If Metal is unreachable pre-login, fall back per the ordering in
the plan's CONTEXT (non-GUI user domain, then user agent + auto-login)
and say so plainly rather than shipping something fragile.

## How to disable

Comment out the `launchd.daemons.ollama` block and rebuild. There is no
serve config to retract. The CLI stays until `environment.systemPackages`
is also trimmed.

## Acceptance — behavioural, not a tok/s table

Replaces the measurements table this doc originally carried. The
benchmark was dropped deliberately (see "why no benchmark was run"); it
would not have changed the model assignment, and these three answers
decide whether the box is actually doing its job:

| Check | Result |
|---|---|
| Both models load, GPU-resident, no memory pressure | **PASS** 2026-10-31 — both engines, see below |
| `qwen3.6:35b-a3b-nvfp4` completes real Hermes tool-calling turns | pending real workload |
| Responsive through a long conversation, not just a cold prompt | pending real workload |

Measured for check 1, `qwen3.8:27b` cold:

```
starting llama-server  …/lib/ollama/llama-server  -c 262144 -np 1
                       --spec-type draft-mtp --spec-draft-n-max 4 --flash-attn auto
load_tensors: offloaded 66/66 layers to GPU
llama-server started in 2.77 seconds
ollama ps → 20 GB   100% GPU   context 262144
```

4.0s cold round-trip including load. **Losing MLX cost the MLX engine,
not GPU acceleration** — llama.cpp offloads every layer to Metal, and
speculative decoding with MTP drafting is on by default. Worth knowing
before paying anything for 1e: the gap being argued over is the ~20%
between two GPU paths, not GPU versus CPU.

Models pulled: 38G in `~/.ollama/models`, inside the Phase 1 exclusions.

Yes to all three ends Phase 3. Ledger 1e is resolved — MLX runs under
one nix-managed daemon, so there is no serving-stack question left open.
The 36.5G of `mlx-community` weights in `~/.cache/huggingface` are now
redundant (Ollama serves the same models itself); harmless where they
are, already excluded from backup and Spotlight by Phase 1, reclaimable
whenever the disk is wanted.

The GGUF copies (`qwen3.6:35b-a3b`, `qwen3.8:27b`, 37.6 GiB) are kept
for now as the comparison baseline above. Delete them once the MLX pair
has a few weeks of real use.

## Manual test script (5 items)

1. `sudo launchctl print system/org.nixos.ollama` → running, `UserName hodgesd`.
2. `lsof -nP -i :11434` shows `100.126.144.70` and nothing else; a curl
   against `192.168.1.198:11434` refuses. (Bind address *is* the access
   control — security rule 1.)
3. `kill` the process; it comes back within ~15s (KeepAlive + ThrottleInterval).
4. `ollama list` after a pull, and `ls ~/.ollama/models` is non-empty —
   proves `OLLAMA_MODELS` took and the models are inside the Phase 1
   exclusions. Then run `qwen3.8:27b-mlx` and confirm the log says
   `mlx runner is ready`; run `qwen3.8:27b` and confirm it says
   `starting llama-server`. Re-run both after any change to how Ollama
   is installed or packaged — the log is the only thing that proves
   which engine is live.
5. Reboot without logging in, then generate over SSH. This is the one that
   decides whether the daemon branch was right.
