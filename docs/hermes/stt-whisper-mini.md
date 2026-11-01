# STT moved to the mini — Whisper large-v3 on Metal

**Status: config landed 2026-11-01, NOT DEPLOYED OR VERIFIED.** Both
hosts eval and the rendered launchd command and STT settings were
checked. Nothing has been deployed, the `tailscale serve` command has not
been run, and no voice note has been transcribed through the new path.

## What was built, and why

Hermes transcribed Telegram voice notes with `faster-whisper` **inside
its own container** on nixos-infra — an 8GB CPU-only VM. The model was
therefore pinned to `small`, which mangles precisely the vocabulary this
homelab is made of: observed in the wild as **"Knicks OS"** for nixos and
**"QUIN 3.8"** for Qwen3.8.

**The motivation is accuracy, not speed.** STT was a few seconds inside a
round trip whose agent turn takes tens of seconds; shaving it was never
the win. `large-v3` is roughly 6× the parameters of `small` and is much
better on proper nouns, jargon and accents.

**The mini, not the MacBook Pro.** A laptop is closed, asleep, or
elsewhere; it cannot answer a voice note that arrives at 06:00. The mini
is the only always-on Apple-silicon host, and it already carries the two
Hermes bridges, so the pattern and the egress shape already existed.

| Piece | Where |
|---|---|
| `whisper-server` + `large-v3` on Metal | `hosts/darwin/mini/whisper-stt.nix` |
| Egress hole for `mini:8323` | `hermes-egress.nix` |
| `stt.provider = "openai"` → the mini | `hermes.nix` |
| Decoder vocabulary biasing | both `--prompt` and `stt.local.initial_prompt` |

### Three things that were verified rather than assumed

Read out of whisper.cpp v1.8.4's own `examples/server/server.cpp`:

- **The OpenAI route is reachable.** whisper-server serves `/inference`
  by default, but `--request-path /v1/audio --inference-path
  /transcriptions` concatenates to `/v1/audio/transcriptions`.
- **The wire matches.** It reads the upload from a multipart field named
  `file`, and its default `response_format` emits `{"text": ...}` —
  exactly OpenAI's shape and field name.
- **ffmpeg is a RUNTIME dependency.** nixpkgs' `withFFmpegSupport`
  asserts Linux-only, but that flag is for the *compiled-in* decoder. The
  `--convert` path shells out to `ffmpeg` on `PATH`
  (`-ar 16000 -ac 1 -c:a pcm_s16le`), so `path = [pkgs.ffmpeg]` is what
  makes it work on darwin. Without it the server decodes WAV only and
  every Telegram voice note — OGG/Opus — would 400.

Also confirmed: `metalSupport ? isDarwin && isAarch64` in nixpkgs, so
Metal is on by default and no override is needed.

### The bug review caught before it ran

`whisper-server` defaults `tmp_dir` to `"."` and builds its transcode
path as `tmp_dir + "/whisper-server-<ts>-<rand>.wav"`. A launchd daemon
starts with cwd `/`, which is not writable — so **every** OGG upload
would have failed its ffmpeg step, i.e. every Telegram voice note, which
is the single thing this service exists to do. The `--convert` discovery
above was necessary but not sufficient.

Fixed with an explicit `--tmp-dir /var/tmp/whisper-stt`, created and
chmod-ed 0700 at launch via `/bin/mkdir` and `/bin/chmod` (outside the
store, same reasoning as `wait4path`), plus `WorkingDirectory` as
insurance for anything else resolving a relative path. Root-owned rather
than bare `/tmp` because the daemon runs as root and the server, not us,
chooses the filename.

### `provider = "openai"` does not mean OpenAI

It selects the openai-multipart *wire* and points it at the mini. **Audio
still never leaves the homelab** — the hard boundary that comment block
in `hermes.nix` has always claimed is intact; it moved from the container
to the mini's GPU. Upstream anticipates self-hosting explicitly: the
`stt.openai` defaults carry `timeout: 60  # allow self-hosted backends
time to cold-start`.

### Reused from studio, not rediscovered

`whisper-server` lives in `/nix/store`, so the daemon carries the
`/bin/wait4path` guard. studio lost its Ollama daemon at **every** boot
to this: `/nix` is a separate APFS volume, launchd can start a daemon
before it mounts, and a *missing executable* makes launchd abandon the
job permanently — `KeepAlive` does not rescue it, because the process
never ran. See `docs/studio/phase-2.md`; its conclusion was "any daemon
whose program lives in the store wants this treatment."

## Known costs, stated plainly

**Availability regression.** The VM was always up. The mini is
FileVault-on with no auto-login, and Tailscale on macOS needs a GUI
session to establish the tunnel. After an unexpected power cut, voice
notes stay broken until someone types the mini's password — they used to
work. Text is unaffected. `stt.provider` is set explicitly, so Hermes
does **not** silently fall back to the in-container model; a dead
endpoint is a failed transcription, which is the honest behaviour.

**A weaker boundary than the other two bridges.** vault-mcp and apple-mcp
check a bearer token. whisper-server has no authentication at all and
cannot check one — Hermes' `Authorization` header is sent and ignored. So
the boundary is the tailnet plus its ACLs alone. The mitigation is that
the endpoint only transcribes audio and stores nothing; if that stops
being acceptable, the fix is a token-checking reverse proxy in front, not
a flag on this server.

**Memory.** ~3GiB of weights held resident plus the Metal working set, on
an M2 Pro that also runs both bridges. Check `vm_stat` after deploying.

**CI.** The mini's closure now includes `whisper-cpp` built with Metal
and CoreML. If nixpkgs' aarch64-darwin cache does not already have that
variant, the mini's build job compiles it — expect a slow first run.

## Credential inventory

| Name | Where | Scope |
|---|---|---|
| — | — | **None added.** `stt.openai.api_key` is the literal placeholder `unused-local-endpoint`; no secret exists for this path and none should be created. |

## Deploy

```bash
just deploy-check && just deploy        # the VM side
# then, on the mini:
darwin-rebuild switch --flake .
tailscale serve --bg --https=8323 http://127.0.0.1:9104   # ONE TIME
```

The `tailscale serve` mapping persists in tailscaled state and is not
managed by nix — same as 8321 and 8322.

## How to disable

| To undo | Do this |
|---|---|
| the whole move | revert `stt.provider` to `"local"` in `hermes.nix`, deploy the VM. The in-container model returns immediately; the mini daemon becomes harmless. |
| the mini service too | drop `./whisper-stt.nix` from `hosts/darwin/mini/default.nix` imports, `darwin-rebuild switch` |
| the network path | remove the `8323` line from `hermes-egress.nix`, deploy |
| the serve mapping | `tailscale serve --https=8323 off` on the mini |

Nothing to rotate — no secret was added.

## Manual test script (5 items)

1. On the mini, straight at the loopback port:
   ```bash
   curl -F file=@/tmp/test.ogg http://127.0.0.1:9104/v1/audio/transcriptions
   ```
   Expect `{"text":"..."}`. The first call pays the model load; subsequent
   ones should be fast. A 400 mentioning audio data means `ffmpeg` is not
   on the daemon's PATH.
2. Through the tailnet, from nixos-infra **as the hermes UID** — your own
   user bypasses the egress chain:
   ```bash
   sudo -u hermes curl -F file=@/tmp/test.ogg \
     https://mini.jaguar-duckbill.ts.net:8323/v1/audio/transcriptions
   ```
3. Send the bot a voice note containing *"deploy the NixOS config and
   check Qwen on the Mac Studio"*. The 🎙️ echo should spell **nixos**,
   **Qwen** and **Studio** correctly — that is the whole point of this
   change, and the regression test for it.
4. `ssh nixos-infra-1 hermes-audit --since -10m` — the turn appears with
   `outcome: ok` and no STT error.
5. Stop the daemon on the mini
   (`sudo launchctl bootout system/org.nixos.whisper-stt`) and send
   another voice note. Hermes must report a failed transcription rather
   than hang or silently answer from a stale transcript. Restore with
   `sudo launchctl bootstrap system /Library/LaunchDaemons/org.nixos.whisper-stt.plist`.
