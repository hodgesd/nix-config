# Hermes Agent (NousResearch) in container mode on the existing Docker
# daemon. The upstream module creates the hermes user/group, runs the agent
# container, and routes the host `hermes` CLI into it via ~/.hermes +
# .container-mode marker for the listed hostUsers.
{
  inputs,
  config,
  lib,
  pkgs,
  ...
}: let
  # ntfy is tailnet-only, so the topic name isn't a secret. Same topic as
  # wan-watch and hermes-sentinel: the one the phone actually subscribes to.
  # (Until 2026-09-13 this used its own hermes-watchdog topic, which the
  # phone wasn't subscribed to, so Hermes-down alerts went nowhere.)
  ntfyUrl = "https://ntfy.jaguar-duckbill.ts.net/hermes-alerts";
  curl = lib.getExe pkgs.curl;
  dockerPkg = config.virtualisation.docker.package;

  # Audit hook lives in /nix/store (mounted read-only in the container) so
  # the agent — which owns everything under /data — cannot rewrite the code
  # that audits it. The nix python3 works in-container for the same reason.
  auditHook = pkgs.writeScript "hermes-audit-hook" ''
    #!${pkgs.python3.interpreter}
    ${builtins.readFile ./hermes-audit-hook.py}
  '';
  auditLog = "/var/lib/hermes/.hermes/logs/audit.jsonl";

  # Phase 0.5 gate 3: policy is served read-only from the store. A store
  # path in extraVolumes also means every policy edit changes the container
  # identity → automatic recreation with the new mount.
  policyFile = pkgs.writeText "hermes-agents-md" (builtins.readFile ./hermes-policy.md);
  # Guard files: the context loader prefers .hermes.md/HERMES.md over
  # AGENTS.md, and the workspace is agent-writable — without these ro
  # shadows the agent could create .hermes.md and outrank its own policy.
  # Empty content falls through to AGENTS.md in the loader.
  emptyContextFile = pkgs.writeText "hermes-empty-context" "";
in {
  imports = [inputs.hermes-agent.nixosModules.default];

  # The hermes module hardcodes ${pkgs.docker}/bin/docker (no package
  # option), and 25.11's default docker (28.5.2) is marked insecure. This
  # host already runs docker_29 (nixos-common.nix); make pkgs.docker mean
  # the same thing so the module's CLI matches the running daemon.
  nixpkgs.overlays = [(final: prev: {docker = prev.docker_29;})];

  # Dotenv format: ANTHROPIC_API_KEY, OPENROUTER_API_KEY, TELEGRAM_BOT_TOKEN,
  # and the Telegram user-ID allowlist. The allowlist stays in ciphertext
  # deliberately — this repo is public. Root-read is fine: systemd resolves
  # EnvironmentFiles as root (same pattern as easy-afd-env).
  #
  # OPENROUTER_API_KEY is LOAD-BEARING (corrected 2026-09-17 — it was
  # previously annotated "unused (cleanup optional)", which was wrong).
  # hermes-agent picks its provider from the credentials present in .env,
  # so this key is what actually selects the OpenRouter path now declared
  # in `model.base_url` below. Removing it does not fall back gracefully to
  # Anthropic — it changes provider resolution, so treat it as config, not
  # as leftovers. Note the .env write is a truncating rewrite
  # (`cat > "$ENV_FILE"` in the upstream activation script), NOT the
  # key-preserving merge that config.yaml gets — so a key deleted here does
  # leave the host file on the next activation.
  #
  # restartUnits for the same reason as easy-afd-env (see default.nix):
  # systemd restarts a service when its unit changes, not when the contents
  # of its EnvironmentFile change — without this, editing the secret (e.g.
  # the allowlist) deploys cleanly but never reaches the running agent.
  sops.secrets.hermes-env.restartUnits = ["hermes-agent.service"];

  services.hermes-agent = {
    enable = true;
    container.enable = true;
    container.hostUsers = ["hodgesd"];

    # Phase 0.5 gate 3: config and policy are read-only to the agent.
    # Bypass this closes (confirmed, not theoretical): config.yaml is
    # owned by the agent's own user and the activation merge preserves
    # agent-ADDED keys across deploys — so a compromised agent could
    # persist e.g. its own mcp_servers entry and reload it by crashing
    # into Restart=always. With these mounts the in-container write path
    # is gone. config.yaml binds the HOST path because the activation
    # merge rewrites it in place (same inode → declared changes still
    # propagate live). Consequence: in-container `hermes config set` /
    # /personality saves fail — config is declarative-only, on purpose.
    # Agent-writable by design: sessions, logs (incl. audit.jsonl —
    # tamper-EVIDENT, not -proof), memories, SOUL.md/MEMORY.md (the
    # identity slot stays agent-managed; policy authority lives in the
    # ro AGENTS.md below, which the guard files keep from being
    # outranked).
    container.extraVolumes = [
      "/var/lib/hermes/.hermes/config.yaml:/data/.hermes/config.yaml:ro"
      "${policyFile}:/data/workspace/AGENTS.md:ro"
      "${emptyContextFile}:/data/workspace/.hermes.md:ro"
      "${emptyContextFile}:/data/workspace/HERMES.md:ro"
    ];
    addToSystemPackages = true;
    # "anthropic" is not in the base env — without it the agent fails at
    # runtime with "The 'anthropic' package is required".
    # "messaging" is the Telegram front end: the bot long-polls Telegram
    # (outbound only, no listener), and the user-ID allowlist in hermes-env
    # is the ONLY authorization boundary in front of an agent that has a
    # shell (terminal.backend = "local" below — inside the container, which
    # has no docker.sock and a read-only /nix/store, but host networking).
    # "voice" carries faster-whisper for LOCAL speech-to-text.
    extraDependencyGroups = ["anthropic" "messaging" "voice"];
    settings = {
      # Provider: OpenRouter, DELIBERATELY (2026-09-17). This used to
      # declare api.anthropic.com and was simply not true — every session
      # from 2026-08-30 to 2026-09-17 recorded
      # billing_base_url = https://openrouter.ai/api/v1 in state.db,
      # including each 05:30 cron run, while config.yaml said Anthropic.
      # hermes-agent resolves the provider itself from the credentials in
      # .env and ignores a model.base_url that disagrees; the declared
      # value bought nothing but a false sense of a gate. Rather than
      # fight the resolver, the config now states what actually happens.
      #
      # This is the right shape for the current exploration phase: the
      # aggregator makes `model.default` a one-line model swap, which is
      # what lets us price DeepSeek et al. against real traffic instead of
      # against published benchmarks. The cost is jurisdictional —
      # OpenRouter guarantees neither US-only nor fixed-provider routing
      # without explicit pinning, and it receives FULL session context
      # (vault reads, Fastmail metadata, Reminders, terminal output).
      # Accepted knowingly, not by accident. Pinning (provider.only +
      # allow_fallbacks: false) is the follow-up once a long-term model is
      # chosen — the plumbing exists upstream (the OpenRouter profile's
      # build_extra_body maps a `provider_preferences` context key onto
      # OpenRouter's `provider` routing object), but the config key that
      # populates it is not yet identified. hermes-sentinel.nix watches
      # for drift from the pair declared here in the meantime.
      #
      # Namespaced model id: both "claude-sonnet-5" and
      # "anthropic/claude-sonnet-5" appear in state.db history. The
      # namespaced form is what OpenRouter actually addresses, so it is
      # unambiguous and matches what the sentinel compares against.
      model.default = "anthropic/claude-sonnet-5";
      model.base_url = "https://openrouter.ai/api/v1";

      # Prompt-cache TTL. Upstream default is "5m"; the only other
      # Anthropic-supported tier is "1h" (hermes_cli/config_defaults.py,
      # `prompt_caching.cache_ttl` — and it applies on the OpenRouter path
      # too, not just the native Anthropic one). This is the money knob:
      # measured 2026-09-17, ~69% of spend was cache WRITES, because
      # Telegram turns land minutes apart and the 5m window expires
      # between them, so each turn repays the full prefix write at
      # 12.5x the read price. Read:write was 2.2:1; target ~10:1.
      # Does nothing for the daily cron — a 24h gap outruns any TTL —
      # so prefix size stays the only lever there.
      prompt_caching.cache_ttl = "1h";

      # Phase 0.5 gate 1: the Telegram surface is minimal by design. The
      # default hermes-telegram preset ships terminal+web+browser+file in
      # one session — that's untrusted web content, a shell, and a
      # dotenv-readable file tool side by side; the user-ID allowlist
      # authenticates senders, not content. Kept: messaging (reply path),
      # todo (internal task list), vision (images Derrick sends). The
      # operator surface is the `hermes` CLI on this host over SSH, which
      # keeps the full default preset (cli is deliberately not listed).
      platform_toolsets.telegram = ["messaging" "todo" "vision"];

      # Voice notes → text, LOCALLY (faster-whisper in the container).
      # No cloud provider, no API key: audio never leaves the homelab.
      # Worth keeping that way now more than before — text prompts go to
      # an aggregator, so local STT is the one part of the pipeline that
      # still has a hard boundary. First use downloads
      # the model from HuggingFace (public 443 — allowed by the egress
      # jail) into /data. "small" trades a few seconds of CPU for
      # noticeably better accuracy than "base" on an 8GB VM.
      stt = {
        enabled = true;
        provider = "local";
        language = "en";
        local.model = "small";
      };
      terminal = {
        backend = "local";
        timeout = 180;
      };
      # No *declared* fallback chain. Note this is a narrower claim than
      # it was before 2026-09-17: it means hermes won't hop to a second
      # configured provider, NOT that inference is pinned to one vendor.
      # Routing inside OpenRouter is the aggregator's to make until the
      # provider-pinning follow-up above lands.
      #
      # MUST stay an explicit [] rather than being deleted: the activation
      # merge preserves existing config keys, so dropping the nix key
      # would leave whatever is already in the host file live.
      fallback_providers = [];

      # Audit trail: log every tool call (terminal, file, and future MCP —
      # no matcher means all tools) as one JSON line with an args DIGEST,
      # no content. This is the observability the whole integration plan's
      # trust model leans on; tail it on the host with `hermes-audit`.
      hooks.post_tool_call = [
        {
          command = "${auditHook}";
          timeout = 10;
        }
      ];
      # Hook first-use consent is a TTY prompt the gateway can never answer
      # (it would silently skip the hook, i.e. no audit trail). Auto-accept
      # does not widen the blast radius: a shell hook runs as the hermes
      # user inside the container, which is exactly what the agent's own
      # terminal tool already does — there is no capability here the agent
      # doesn't have. The declared hook itself is in the read-only store.
      hooks_auto_accept = true;
    };
    environmentFiles = [config.sops.secrets.hermes-env.path];

    # The container is UTC by default, which silently shifts cron
    # schedules (the 05:30 daily-note job would fire at 00:30 CT). Set TZ
    # at the CONTAINER level, not via `environment`: that option merges
    # into the dotenv, which hermes loads after Python starts — too late
    # for timezone initialization. --env reaches PID 1 before anything
    # runs, so "30 5 * * *" means 05:30 Chicago, DST included.
    container.extraOptions = ["--env" "TZ=America/Chicago"];

    # Agent policy (hermes-policy.md): tiers, injection rules, escalation.
    # Delivered as workspace AGENTS.md because that's the file the gateway
    # injects into every session's system prompt (prompt_builder loads
    # context files from the module-set terminal.cwd = /data/workspace;
    # SOUL.md would need to live in HERMES_HOME, which `documents` can't
    # reach). Since Phase 0.5 it arrives via the read-only store mount in
    # container.extraVolumes above — NOT via `documents`, whose installed
    # copy would be agent-owned and editable. WARNING (learned in 0.5
    # validation): the host file at /var/lib/hermes/workspace/AGENTS.md is
    # the bind mount's ANCHOR, not clutter — host and volume share a
    # filesystem, so rm'ing it while the container runs unlinks the
    # mountpoint dentry, silently detaches the ro shadow, and leaves the
    # path agent-writable. Never remove it; docker recreates it empty at
    # container creation if absent.
  };

  # The upstream module copies the rendered config.yaml into $HERMES_HOME at
  # activation but does not restart the agent — a settings change (e.g. the
  # model switch) otherwise deploys cleanly while the running process keeps
  # the old config. Same failure class as the hermes-env restartUnits above.
  systemd.services.hermes-agent.restartTriggers = [
    (builtins.toJSON config.services.hermes-agent.settings)
  ];

  # The hook writes audit.jsonl inside the container's bind mount; hooks
  # can't reach the host journal from in there, so a host-side tail bridges
  # the file into journald under a stable identifier. -n0 skips history on
  # (re)start — the file itself keeps the full record; journald gets the
  # live stream. tail -F tolerates the file not existing yet (first boot,
  # or before the first tool call ever fires).
  systemd.services.hermes-audit-forwarder = {
    description = "Forward hermes tool-call audit log to journald";
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      ExecStart = "${pkgs.coreutils}/bin/tail -n0 -F ${auditLog}";
      SyslogIdentifier = "hermes-audit";
      # Matches the file's hermes:hermes 0660 (dirs 2770) from the upstream
      # module's activation script.
      User = "hermes";
      Group = "hermes";
      Restart = "always";
      RestartSec = 5;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ReadOnlyPaths = ["/var/lib/hermes/.hermes/logs"];
      PrivateTmp = true;
    };
  };

  # `hermes-audit` = live tail of the audit stream; any extra args are
  # passed straight to journalctl (e.g. `hermes-audit --since -1h`).
  #
  # sqlite: /var/lib/hermes/.hermes/state.db is the ONLY place hermes keeps
  # per-session token and cost accounting (tables `sessions` and
  # `session_model_usage`: input/output/cache_read/cache_write/reasoning +
  # estimated_cost_usd). The logs carry none of it. This VM shipped without
  # sqlite3 *and* without python3, so the 2026-09-17 provider/cost
  # investigation had to scp the db to a Mac to read it. Query it in place:
  #   sqlite3 -readonly /var/lib/hermes/.hermes/state.db \
  #     "select model, billing_base_url, output_tokens, cache_write_tokens
  #      from session_model_usage order by last_seen desc limit 5;"
  # No sudo needed — hodgesd is in the `hermes` group (sudo here wants a
  # password; group access does not).
  environment.systemPackages = [
    pkgs.sqlite
    (pkgs.writeShellScriptBin "hermes-audit" ''
      if [ $# -eq 0 ]; then
        exec journalctl -t hermes-audit -n 50 -f
      fi
      exec journalctl -t hermes-audit "$@"
    '')
  ];

  # Watchdog: a dead Telegram bot is indistinguishable from a quiet day
  # so check the unit AND the container every 5 minutes and alert via ntfy,
  # edge-triggered (one alert per outage), the pattern hermes-sentinel.nix
  # also uses. Known blind spot: a poller wedged inside a healthy container
  # isn't caught — that would need a heartbeat into a Gatus external
  # endpoint (gatus.nix).
  systemd.services.hermes-watchdog = {
    description = "Watch hermes-agent, alert via ntfy";
    serviceConfig = {
      Type = "oneshot";
      # Holds the flag file that makes alerting edge-triggered.
      StateDirectory = "hermes-watchdog";
    };
    script = ''
      set -u
      flag="$STATE_DIRECTORY/down"

      notify() {
        ${curl} -fsS -m 10 \
          -H "Title: $1" \
          -H "Priority: $2" \
          -H "Tags: $3" \
          -d "$4" \
          ${lib.escapeShellArg ntfyUrl} >/dev/null || true
      }

      ok=1
      ${pkgs.systemd}/bin/systemctl is-active --quiet hermes-agent.service || ok=0
      [ "$(${dockerPkg}/bin/docker inspect -f '{{.State.Running}}' hermes-agent 2>/dev/null)" = "true" ] || ok=0

      if [ "$ok" = 1 ]; then
        if [ -e "$flag" ]; then
          notify "Hermes agent recovered" default white_check_mark \
            "hermes-agent on nixos-infra is running again."
          rm -f "$flag"
        fi
      else
        # Edge-triggered: alert once per outage, not every 5 minutes.
        if [ ! -e "$flag" ]; then
          notify "Hermes agent is DOWN" urgent rotating_light \
            "hermes-agent.service or its container is not running on nixos-infra. The Telegram bot is offline."
          touch "$flag"
        fi
      fi
    '';
  };

  systemd.timers.hermes-watchdog = {
    wantedBy = ["timers.target"];
    timerConfig = {
      # Give docker and the agent container time to come up after boot.
      OnBootSec = "5m";
      OnUnitActiveSec = "5m";
      Persistent = true;
    };
  };
}
