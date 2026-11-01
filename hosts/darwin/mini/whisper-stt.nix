# Whisper STT endpoint for Hermes — large-v3 on Metal, loopback only.
#
# WHY THIS EXISTS: Hermes's voice path ran faster-whisper *in its own
# container* on nixos-infra — an 8GB CPU-only VM, so the model was pinned
# to "small" and mangled exactly the vocabulary this homelab is made of
# ("Knicks OS" for nixos, "QUIN 3.8" for Qwen3.8). The fix is a bigger
# model on a GPU, and the mini is the only always-on Apple-silicon box.
# NOT a laptop: a closed MacBook cannot answer a voice note that arrives
# at 06:00.
#
# Accuracy is the point, not speed. STT was a few seconds of a round trip
# whose agent turn takes tens; large-v3 is 6x the parameters of small.
#
# AVAILABILITY REGRESSION, stated plainly: the VM was always up. This box
# is FileVault-on with no auto-login (see the long comment in
# default.nix), and Tailscale on macOS needs a GUI session to establish
# the tunnel (docs/studio/phase-2.md). So after an unexpected power cut,
# voice notes stay broken until someone types the mini's password —
# whereas before they worked. Text is unaffected. Hermes's own
# autodetect ladder does NOT silently fall back to the in-container
# model, because `stt.provider` is set explicitly; a dead endpoint is a
# failed transcription, which is the honest behaviour.
#
# Disable: drop this file from default.nix's imports, revert hermes.nix's
# `stt.provider` to "local", deploy both. The in-container model returns.
{
  username,
  pkgs,
  lib,
  ...
}: let
  # Metal is on by default for aarch64-darwin in nixpkgs (package.nix:
  # `metalSupport ? isDarwin && isAarch64`), as is CoreML with
  # ALLOW_FALLBACK — so no override is needed and `--no-gpu` is the
  # only way to lose GPU acceleration. CoreML would additionally want a
  # generated .mlmodelc beside the weights; absent one it falls back to
  # Metal, which is what we are relying on.
  whisper = pkgs.whisper-cpp;

  # ggml large-v3, 2.9GiB. Pinned by hash, so if HuggingFace's `main`
  # ever moves under us the build fails loudly instead of silently
  # swapping the model. Hash verified against a real download
  # 2026-11-01. The cheaper swap, if first-token latency disappoints:
  # ggml-large-v3-turbo.bin (~1.6GiB, distilled, several times faster,
  # marginally worse on rare words — which is the thing we came here to
  # fix, hence not the default).
  model = pkgs.fetchurl {
    url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin";
    hash = "sha256-ZNGCtEC5jVIDxPm9VBVE2ExgUZbE97hF36EfsjWU0eI=";
  };

  port = 9104; # loopback; 9102 = vault-mcp, 9103 = apple-mcp

  # --convert's scratch space. NOT optional: whisper-server v1.8.4
  # defaults `tmp_dir` to "." and builds the transcode path as
  # tmp_dir + "/whisper-server-<ts>-<rand>.wav" (generate_temp_filename),
  # while a launchd daemon starts with cwd = "/" — which is not writable.
  # Every OGG upload would therefore fail its ffmpeg step, i.e. every
  # Telegram voice note, which is the one thing this service exists to
  # do. Caught in review on PR #115 before it ever ran.
  #
  # /var/run, NOT /var/tmp. The parent must not be world-writable, or an
  # unprivileged local user can pre-create this path as a SYMLINK: a
  # root `mkdir -p` accepts an existing symlink-to-dir, and the root
  # `chmod 700` below then follows it and applies 0700 to the target.
  # Pointed at /Users that locks every account out of its own home.
  # CWE-59, raised in review on PR #115; /var/tmp is mode 1777, so the
  # first version of this was genuinely exposed.
  #
  # /var/run is root-owned and not world-writable, which removes the
  # pre-creation step entirely. The launch command still refuses to
  # proceed if the path is a symlink — belt and braces, because this
  # assumes a permission bit on a host nobody can inspect from CI, and
  # failing closed is the cheap side of that bet.
  tmpDir = "/var/run/whisper-stt";
in {
  # Model weights held resident: ~3GiB plus Metal working set. The mini
  # is an M2 Pro also running both MCP bridges — check `vm_stat` after
  # deploying if anything starts swapping, and drop to -turbo if so.
  environment.systemPackages = [whisper]; # whisper-cli, for hand-testing

  launchd.daemons.whisper-stt = {
    # ffmpeg is a RUNTIME dependency, not a build flag. nixpkgs'
    # `withFFmpegSupport` (compiled-in) asserts Linux-only, but the
    # server's `--convert` path shells out to an ffmpeg on PATH:
    #   ffmpeg -i <in> -y -ar 16000 -ac 1 -c:a pcm_s16le <out>
    # Without it the server only decodes WAV, and Telegram voice notes
    # arrive as OGG/Opus — so every transcription would 400.
    path = [pkgs.ffmpeg];
    serviceConfig = {
      # A SYSTEM daemon, not a user agent, deliberately. The two bridges
      # in default.nix are user agents because they live in the user's
      # iCloud session (vault files, EventKit). Whisper needs no session
      # at all, so it should not inherit the dependency — it starts as
      # soon as the box is unlocked, without waiting for a GUI login.
      #
      # /bin/wait4path is not decoration. studio lost its Ollama daemon
      # at every boot to exactly this (docs/studio/phase-2.md): /nix is a
      # separate APFS volume, launchd can start a daemon before it is
      # mounted, and a *missing executable* makes launchd ABANDON the job
      # permanently — KeepAlive does not rescue it, because the process
      # never ran. /bin/sh and /bin/wait4path live outside the store so
      # launchd can always exec them; `exec` then replaces the shell so
      # launchd still supervises the real process. That file's conclusion
      # was "any daemon whose program lives in the store wants this
      # treatment" — this is one.
      ProgramArguments = [
        "/bin/sh"
        "-c"
        # --host 127.0.0.1: loopback ONLY. The tailnet reaches this via
        # `tailscale serve` (see the one-time command below), matching
        # the vault/apple bridges. NEVER 0.0.0.0, never a LAN address:
        # whisper-server has no authentication whatsoever, so its bind
        # address is the entire access control.
        #
        # --request-path + --inference-path concatenate to
        # /v1/audio/transcriptions, which is what makes this endpoint
        # OpenAI-compatible: hermes-agent's `openai` STT provider POSTs
        # multipart to {base_url}/audio/transcriptions with the file in a
        # field named `file`, and the server's default response_format
        # emits {"text": ...} — verified against whisper.cpp v1.8.4
        # source, not assumed.
        #
        # --prompt is the same decoder-biasing trick as hermes.nix's
        # stt.local.initial_prompt, applied server-side. Both are kept:
        # this one is live, that one covers the in-container fallback if
        # provider is ever reverted to "local". Keep them in sync.
        (lib.concatStringsSep " " [
          "/bin/wait4path ${whisper}/bin/whisper-server &&"
          # /bin/mkdir and /bin/chmod, not coreutils from the store: same
          # reasoning as wait4path above — these run BEFORE the store is
          # guaranteed, and /bin is always there. mkdir -m only applies on
          # creation, hence the explicit chmod for a pre-existing dir.
          # `cd` is a shell builtin and runs AFTER mkdir, which is the
          # only safe place for it. A launchd `WorkingDirectory = tmpDir`
          # looks equivalent and is not: launchd chdir()s before exec, so
          # on a first deploy -- the mini's actual state -- it would fail
          # to enter a directory this line has not created yet, and the
          # job would die before /bin/sh ever ran. Caught in review on
          # PR #115 after I added it as "insurance"; it was a bootstrap
          # deadlock. --tmp-dir is absolute and does the real work.
          # Order matters: reject a symlink BEFORE the chmod that would
          # follow one. `!` keeps this inside the && chain -- not a
          # symlink, carry on; symlink, the chain stops, sh exits
          # non-zero and KeepAlive retries every 15s rather than
          # chmod'ing an attacker's target. Fail closed, loudly, in the
          # log. The residual TOCTOU between test and chmod is not
          # exploitable with a root-owned parent.
          "! [ -L ${tmpDir} ] && /bin/mkdir -p ${tmpDir} && /bin/chmod 700 ${tmpDir} && cd ${tmpDir} &&"
          "exec ${whisper}/bin/whisper-server"
          "--model ${model}"
          "--tmp-dir ${tmpDir}"
          "--host 127.0.0.1"
          "--port ${toString port}"
          "--request-path /v1/audio"
          "--inference-path /transcriptions"
          "--convert"
          "--language en"
          "--prompt"
          (lib.escapeShellArg
            ("Notes on the homelab: NixOS, nix-darwin, Nix flakes, sops-nix, "
              + "Proxmox, Tailscale and MagicDNS, Gatus, Obsidian, Ollama, MLX, "
              + "Qwen, Hermes, OpenRouter, Fastmail, UniFi, Synology. "
              + "Flight department notes: Gulfstream, Challenger, FOQA, ASAP, "
              + "IS-BAO, Teterboro, Part 91, MEL, recurrent training."))
        ])
      ];
      RunAtLoad = true;
      # A crash relaunches. Unlike studio's Ollama there is no address to
      # race for (loopback is always up), so this is plain crash-restart
      # rather than a bind retry.
      KeepAlive = true;
      ThrottleInterval = 15;
      StandardOutPath = "/Users/${username}/Library/Logs/whisper-stt.log";
      StandardErrorPath = "/Users/${username}/Library/Logs/whisper-stt.log";
    };
  };

  # Bound the scratch directory. whisper-server LEAKS on failure, which
  # is confirmed in v1.8.4's source rather than suspected: when ffmpeg
  # exits non-zero, `convert_to_wav` returns false without unlinking
  # either the upload or the partial `<name>_temp.wav`, and the handler
  # just returns 500. The `read_audio_data` failure path leaks the same
  # way. So every rejected upload costs disk permanently.
  #
  # That matters here specifically because the endpoint has NO
  # authentication (see the serve note below): anyone who can reach it
  # on the tailnet can repeat a malformed upload and fill the mini's
  # disk, taking the vault and Apple bridges down with it. CWE-459,
  # raised in review on PR #115.
  #
  # Transcodes finish in seconds, so anything older than an hour is
  # garbage by definition. /usr/bin/find is a system binary, outside the
  # store, so this job has no /nix dependency and needs no wait4path.
  #
  # HONEST RESIDUAL: this bounds growth, it does not impose a quota. A
  # flood faster than hourly still fills the disk. The actual fix is
  # authentication in front of the endpoint; this is the cheap mitigation
  # that makes the slow version harmless.
  launchd.daemons.whisper-stt-reap = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        "/usr/bin/find ${tmpDir} -type f -mmin +60 -delete 2>/dev/null || true"
      ];
      RunAtLoad = true;
      StartInterval = 3600;
      # One-shot per fire: it prunes and exits. KeepAlive would respawn
      # it in a loop (the lesson from studio's gpu-wired-limit daemon).
      KeepAlive = false;
      StandardErrorPath = "/Users/${username}/Library/Logs/whisper-stt.log";
    };
  };

  # ONE-TIME, on the mini, same as the two bridges (persisted in
  # tailscaled state, not managed by nix — that is why it is a comment
  # and not config):
  #
  #   tailscale serve --bg --https=8323 http://127.0.0.1:9104
  #
  # Port 8323 continues the bridge sequence (8321 vault, 8322 apple).
  # Unlike those two, there is NO bearer token here: whisper-server
  # cannot check one, and Hermes' Bearer header would be ignored. So the
  # boundary is the tailnet plus its ACLs alone, which is a WEAKER
  # posture than the other two bridges — the honest mitigation is that
  # the endpoint only transcribes audio and holds no data. If that stops
  # being acceptable, the fix is a token-checking reverse proxy in front,
  # not a flag on this server.
  #
  # Verify (from the mini):
  #   curl -F file=@/tmp/test.ogg http://127.0.0.1:9104/v1/audio/transcriptions
  # Expect {"text":"..."}; first call pays the model load.
}
