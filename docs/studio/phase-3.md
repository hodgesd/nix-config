# Phase 3 — studio: Ollama serving

**Status: switched on studio 2026-10-31 — daemon up, bound to
`100.126.144.70:11434`, no serve config. Acceptance checks below PENDING
the two model pulls.**

## What was built

`hosts/darwin/studio/default.nix`:

| Thing | Detail |
|---|---|
| Package | `unstablePkgs.ollama` — **0.34.3** at our locked rev, past the 0.19 that added the Apple-silicon MLX backend. No brew fallback needed. |
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

nix-darwin writes it into `/etc/zshenv`, which non-interactive SSH
commands do source, so `ssh studio 'ollama pull …'` works unattended.

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

### Model assignment, and why no benchmark was run

Both production models are MLX, because MLX *and* MoE are jointly
available — the tradeoff an earlier draft reasoned about does not exist:

| Workload | Model | Architecture | Size |
|---|---|---|---|
| Hermes, tool calling | `qwen3.6:35b-a3b-nvfp4` | MoE, 256 experts / 8 active | 21.5 GiB |
| Code review, reasoning, vision | `qwen3.8:27b-mlx` | dense 27B | 16.9 GiB |

`qwen3.6:35b-a3b-nvfp4` rather than its alias `qwen3.6:35b-mlx`: same
bytes, but the explicit tag names the architecture and quantization, so
the next reader does not have to re-derive what this section just had
to.

Both resident = 38.4 GiB, comfortable under the 81.5 GiB ceiling, and
`OLLAMA_MAX_LOADED_MODELS = 2` keeps both hot so they do not evict each
other.

A formal GGUF-vs-MLX benchmark was deliberately **not** made a gate on
this phase: MLX is the expected winner on this hardware, both chosen
models are MLX, and a tok/s table would not change either assignment.
`qwen3.6:35b-a3b` (GGUF, 21.1 GiB) is kept only as an optional
comparison. The acceptance criteria below are behavioural instead.

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
| Both models load, GPU-resident, no memory pressure | |
| `qwen3.6:35b-a3b-nvfp4` completes real Hermes tool-calling turns | |
| Responsive through a long conversation, not just a cold prompt | |

Yes to all three ends Phase 3. Phase 3b stays unopened unless one of
them fails — and no longer on model-coverage grounds, since Ollama
serves a 4-bit MLX MoE itself. The 36.5G of `mlx-community` weights in
`~/.cache/huggingface` are now redundant; harmless where they are
(already excluded from backup and Spotlight by Phase 1), reclaimable
whenever the disk is wanted.

## Manual test script (5 items)

1. `sudo launchctl print system/org.nixos.ollama` → running, `UserName hodgesd`.
2. `lsof -nP -i :11434` shows `100.126.144.70` and nothing else; a curl
   against `192.168.1.198:11434` refuses. (Bind address *is* the access
   control — security rule 1.)
3. `kill` the process; it comes back within ~15s (KeepAlive + ThrottleInterval).
4. `ollama list` after a pull, and `ls ~/.ollama/models` is non-empty —
   proves `OLLAMA_MODELS` took and the models are inside the Phase 1
   exclusions. Then run `qwen3.8:27b-mlx` once and confirm the log names
   the **MLX** runner: a registry tag proves the model exists, not that
   this build executes it on that engine. If it silently falls back to
   llama.cpp, the dense/MLX half of the assignment above is void.
5. Reboot without logging in, then generate over SSH. This is the one that
   decides whether the daemon branch was right.
