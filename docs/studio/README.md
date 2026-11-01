# studio

**Status: Phases 0–4 done — serving models over the tailnet, watched from
nixos-infra.** Phase 5 (remote Nix builder) was declined on a
measurement; 6 and 7 are decision-gated. Phase 8 — letting Hermes use
the local model — has its **repo-side wiring landed** (the egress line
and a named `providers.studio` provider) but is **not deployed or
verified**, and `model.default` still routes every turn to Sonnet. See
[`phase-8.md`](phase-8.md) for the four prerequisites it had to resolve
first.

The Mac Studio (M5 Ultra, 96GB) is a dedicated local-inference box: model
serving only, deliberately nothing else. `nixos-infra` stays the monitoring
and control plane and watches it; the `mini` keeps the Hermes Apple/vault
bridges, which need its iCloud session. It carries no Apple ID.

Ollama runs as a system LaunchDaemon bound to the node's MagicDNS name —
`studio.jaguar-duckbill.ts.net:11434`, the tailscale interface alone.
Nothing listens on the LAN or the internet; the API has no authentication,
so the bind address *is* the access control. A system daemon rather than a
user agent because FileVault is off here, so the box boots to loginwindow
unattended and the service comes back with nobody logged in.

Ollama ships two engines behind one API — llama.cpp for GGUF and MLX for
Apple silicon — selected per model by tag. nixpkgs can't build the MLX
runtime (`mlx.metallib` is precompiled Metal shaders, and compiling Metal
needs full Xcode), so the config pulls that one artifact from upstream's
own release of the same version, pinned by hash. One nix-managed daemon, no
Homebrew, no Xcode. It is worth the trouble — measured warm on a prose
prompt, `num_predict=200`:

| Model | MLX | llama.cpp |
|---|---|---|
| `qwen3.6:35b-a3b` — MoE, 256 experts / 8 active | **239 tok/s** | 108 tok/s |
| `qwen3.8:27b` — dense | **100 tok/s** | 50 tok/s |

~2× either way. Benchmark honestly if you repeat this: both engines use
MTP speculative decoding, so a predictable prompt ("count to 60") measures
draft acceptance instead and reports up to 45% higher. See
[`phase-3.md`](phase-3.md) for the full plan,
per-phase notes, and the traps — several Ollama tags alias one manifest,
so models must be identified by digest rather than name.

Unlike the mini, FileVault is deliberately **off** here (decided
2026-10-30): the box is physically secure, has no Apple ID and holds no
personal data beyond re-downloadable model weights, and availability is
the point. Apple silicon still encrypts the SSD in hardware. So it boots
back on its own after a reboot or power cut, with no pre-boot unlock to
perform.

That turned out to be necessary but not sufficient: tested 2026-10-31,
an unattended reboot came back with **no tailnet**. Tailscale's macOS GUI
app launches at boot but can't establish the tunnel without a login
session, so Ollama couldn't bind its MagicDNS name and the box was
reachable only on the LAN. The fix is auto-login — available precisely
because FileVault is off — which costs an unlocked desktop and is
deliberately *not* copied to the mini. See
[`phase-2.md`](phase-2.md) for the diagnosis and
the `tailscaled`-as-system-daemon alternative.

## Files

- [claude-code-prompt.md](claude-code-prompt.md): the phased plan and per-phase execution prompt.
- [phase-0.md](phase-0.md) to [phase-4.md](phase-4.md): what each phase changed, verified, and decided.
- [phase-8.md](phase-8.md): the Hermes integration — measured prerequisites, the brief-only trial protocol, and the local-model probe results.
- [scoring-probe.py](scoring-probe.py), [scoring-multiturn.py](scoring-multiturn.py): the tool-use probes behind phase-8.md's results.
- Host config: `hosts/darwin/studio/default.nix`.
