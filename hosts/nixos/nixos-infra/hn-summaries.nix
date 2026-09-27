# hn-summaries — one Hacker News discussion summary per story, shared by the
# Macs' daily_news SwiftBar plugin instead of each Mac paying OpenRouter for
# the same thread. A native systemd service (hn-summaries/server.py: aiohttp +
# beautifulsoup4 + sqlite3, no framework) plus a 30-minute warmer that
# summarises the current front page so the Macs' refreshes are cache hits.
# The thread flattening and the summary contract are the plugin's own code,
# copied verbatim, so both sides render the same tooltip.
#
# Reachability: binds :8090 on all interfaces, but the firewall in
# hosts/common/nixos-common.nix trusts tailscale0 only, so the Macs reach
# http://nixos-infra-1:8090 over WireGuard and the LAN gets nothing — the same
# arrangement as easy-afd (:8000) and Gatus (:8080). Plain HTTP on purpose:
# machine-to-machine JSON on an encrypted tailnet, no ts-* sidecar (that
# pattern is for browser-facing TLS). Never add the port to allowedTCPPorts.
#
# Spend: a dedicated OpenRouter key (sops hn-summaries-env, credit-limited at
# OpenRouter), a daily cap, single-flight per story, a per-call timeout and an
# input budget — the settings below. `journalctl -u hn-summaries | grep llm`
# is the ledger: one line per paid call with tokens and cost.
#
# Disable: remove ./hn-summaries.nix from default.nix imports and deploy; the
# plugin falls back to local cache → HN Companion → local llm on its own.
# State to delete afterwards: /var/lib/private/hn-summaries. Then revoke the
# key at OpenRouter and drop the sops entry.
{
  config,
  lib,
  pkgs,
  ...
}: let
  # ── Settings ────────────────────────────────────────────────────────────
  # Free port: 8000 easy-afd, 8080 gatus, 8321/8322 hermes egress, 9101-9103
  # MCP loopback are taken (repo grep + `ss -ltn` on the VM, 2026-09-26).
  # gatus.nix polls this port by number; change both together.
  port = 8090;
  # OpenRouter model id. 2026-09-26 bake-off on five front-page threads:
  # gpt-5-mini at minimal effort was the most accurate and the cheapest
  # (2.5-4.4 s, ~$0.003 a story); gemini-2.5-flash at reasoning low was 3×
  # slower, 2× the cost and stalled past 60 s twice.
  model = "openai/gpt-5-mini";
  reasoningEffort = "minimal"; # sent as reasoning.effort; "" sends none
  # Caps runaway output, and OpenRouter's per-call credit hold: it reserves
  # the model's full output limit up front, so a low balance fails with 402
  # for a 300-token reply without this.
  maxTokens = 4096;
  # Paid calls per UTC day, warmer included; after that the service answers
  # from cache and HN Companion only and logs once. The front page turns over
  # ~30-50 stories a day and Companion covers most of them.
  dailyLlmCap = 60;
  llmTimeout = 30; # seconds per paid call
  threadCharBudget = 80000; # chars of thread text per story, ~20k input tokens
  missTtlHours = 6; # a story whose paid call failed is not retried sooner
  pyEnv = pkgs.python3.withPackages (ps: [ps.aiohttp ps.beautifulsoup4]);
  app = ./hn-summaries/server.py;

  # Same set easy-afd.nix uses, plus no socket families beyond IP: the
  # process only ever talks HTTP(S) to Algolia, Companion and OpenRouter.
  hardening = {
    NoNewPrivileges = true;
    PrivateTmp = true;
    ProtectSystem = "strict"; # everything RO except StateDirectory
    ProtectHome = true;
    ProtectKernelTunables = true;
    ProtectControlGroups = true;
    RestrictNamespaces = true;
    LockPersonality = true;
    RestrictAddressFamilies = ["AF_INET" "AF_INET6"];
  };
in {
  # Dotenv: OPENROUTER_API_KEY=… — a key created for this service alone, so its
  # spend limit and revocation touch nothing else. restartUnits for the reason
  # default.nix explains: systemd doesn't notice EnvironmentFile content
  # changes, so a rotated key would otherwise sit unused until the next reboot.
  sops.secrets.hn-summaries-env.restartUnits = ["hn-summaries.service"];

  systemd.services.hn-summaries = {
    description = "Shared Hacker News discussion summaries for the daily_news plugin";
    wantedBy = ["multi-user.target"];
    after = ["network-online.target"];
    wants = ["network-online.target"];

    environment = {
      HN_PORT = toString port;
      HN_MODEL = model;
      HN_REASONING_EFFORT = reasoningEffort;
      HN_MAX_TOKENS = toString maxTokens;
      HN_DAILY_LLM_CAP = toString dailyLlmCap;
      HN_LLM_TIMEOUT = toString llmTimeout;
      HN_THREAD_CHAR_BUDGET = toString threadCharBudget;
      HN_MISS_TTL_HOURS = toString missTtlHours;
      PYTHONUNBUFFERED = "1"; # ledger lines reach the journal as they happen
    };

    # Unit-level, not serviceConfig — see easy-afd.nix for why.
    startLimitBurst = 5;
    startLimitIntervalSec = 60;

    serviceConfig =
      hardening
      // {
        # No fixed user: nothing else needs to share files with it. The
        # SQLite db lives in /var/lib/private/hn-summaries (StateDirectory
        # under DynamicUser) and is deliberately not backed up: every row can
        # be regenerated, and the ledger is also in the journal.
        DynamicUser = true;
        StateDirectory = "hn-summaries";
        ExecStart = "${pyEnv}/bin/python3 ${app}";
        # Read by systemd as root before dropping privileges (the secret is
        # root-only 0400), same as every other EnvironmentFile on this host.
        EnvironmentFile = config.sops.secrets.hn-summaries-env.path;
        # "always", not "on-failure": a clean exit is still an outage.
        Restart = "always";
        RestartSec = "5s";
      };
  };
}
