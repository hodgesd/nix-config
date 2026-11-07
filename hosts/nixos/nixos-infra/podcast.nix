# Read-later podcast: send an article URL (or pasted text), get an episode
# in a private podcast feed that Overcast polls. docs/PODCAST.md has the
# Shortcut, the checks and the runbook.
#
# Shape:
#   - podcast.service (native, podcast/server.py): intake API on :8095,
#     queue + episode list in SQLite, worker that fetches, cleans for
#     speech (podcast/speech.py), calls Kokoro, joins with ffmpeg and
#     rewrites feed.xml. Native rather than a container because this repo
#     has no image build or registry, and nixpkgs already carries
#     trafilatura and ffmpeg; same pattern as hn-summaries and Gatus.
#   - stacks/podcast (compose-podcast.service): Kokoro TTS on VM loopback
#     :8880, and ts-podcast, a dedicated tailnet node "podcast".
#   - mcp-podcast.service: Hermes's podcast_this tool (podcast/mcp_server.py).
#
# Exposure (the SECURITY note on the serve.json template below is the
# authority): ts-podcast :443 is on Funnel and serves only /p/<token>/
# (feed.xml + MP3s). ts-podcast :8444 is the tailnet-only HTTPS front for
# the intake. Kokoro and :8095 are not on Funnel; :8095 is tailnet-only
# like every other port on this VM (nixos-common.nix firewall).
#
# Disable: remove ./podcast.nix from default.nix imports and deploy, then
# on the VM `docker compose --project-directory /srv/podcast down` (the
# compose unit is a oneshot with no stop action, so its containers outlive
# it; this also takes the Funnel down). Then delete /var/lib/podcast and
# /srv/podcast, remove the "podcast" node in the Tailscale admin console and
# drop the three podcast-* sops keys. Overcast keeps its last copy of the
# feed until you unsubscribe.
{
  config,
  lib,
  pkgs,
  ...
}: let
  # ── Settings ────────────────────────────────────────────────────────────
  # Free on the VM (`ss -ltn`, 2026-11-06): 8000 easy-afd, 8080 gatus, 8090
  # hn-summaries, 8091 bj-drill api, 9101/9102 MCP. gatus.nix does not
  # poll these by number; the check below goes through ts-podcast.
  port = 8095; # intake, podcast.service
  kokoroPort = 8880; # loopback publish in stacks/podcast
  mcpPort = 9105; # podcast_this tool (9104 is the mini's whisper port)
  intakeTailnetPort = 8444; # ts-podcast, tailnet only. Funnel can't serve
  #                           this port at all (443, 8443, 10000 only).
  # Kokoro voice. af_heart: the only grade-A voice in hexgrad's
  # Kokoro-82M VOICES.md (af_bella is A-, the male voices C+ or lower),
  # Kokoro-FastAPI's default, and the voice the 2.4x real-time figure in
  # docs/PODCAST.md was measured with. American English, calm pace; it
  # holds up over a 20-minute article better than the brighter voices.
  voice = "af_heart";
  retentionDays = 30;
  publicBase = "https://podcast.jaguar-duckbill.ts.net";
  stateDir = "/var/lib/podcast";

  pyEnv = pkgs.python3.withPackages (ps: [ps.trafilatura]);
  mcpEnv = pkgs.python3.withPackages (ps: [ps.fastmcp]);
  # Just the two runtime modules; tests and fixtures stay out of the store.
  app = lib.fileset.toSource {
    root = ./podcast;
    fileset = lib.fileset.unions [./podcast/server.py ./podcast/speech.py];
  };

  # Feed artwork, 3000 px square (Apple's maximum; Overcast scales down).
  cover = pkgs.runCommand "podcast-cover.png" {nativeBuildInputs = [pkgs.librsvg];} ''
    rsvg-convert -w 3000 -h 3000 ${./podcast/cover.svg} -o $out
  '';

  ph = config.sops.placeholder;
in {
  # Three raw values (no dotenv blobs), so templates can place each one
  # exactly where it is needed and nowhere else:
  #   podcast-intake-token  bearer for POST /enqueue (Shortcut, Hermes tool)
  #   podcast-feed-token    the /p/<token>/ path segment of the public feed
  #   podcast-ts-authkey    Tailscale auth key, tagged tag:podcast, for ts-podcast
  sops.secrets = {
    podcast-intake-token = {};
    podcast-feed-token = {};
    podcast-ts-authkey = {};
  };

  sops.templates = {
    # restartUnits: systemd does not notice EnvironmentFile content changes
    # (see default.nix), so a rotated token would otherwise sit unused.
    podcast-env = {
      content = ''
        PODCAST_INTAKE_TOKEN=${ph.podcast-intake-token}
        PODCAST_FEED_TOKEN=${ph.podcast-feed-token}
      '';
      restartUnits = ["podcast.service"];
    };
    podcast-mcp-env = {
      content = ''
        PODCAST_INTAKE_TOKEN=${ph.podcast-intake-token}
        PODCAST_INTAKE_URL=http://127.0.0.1:${toString port}/enqueue
        PODCAST_MCP_PORT=${toString mcpPort}
      '';
      restartUnits = ["mcp-podcast.service"];
    };
    # Compose interpolation only; read once by `docker compose up`.
    podcast-compose-env.content = ''
      TS_AUTHKEY=${ph.podcast-ts-authkey}
    '';
    # Bind-mounted by path in stacks/podcast/docker-compose.yml; keep the
    # name in sync. Like sidecars.nix, an edit needs `docker restart
    # ts-podcast` (compose does not recreate for a bind mount's contents).
    "ts-podcast-serve.json".content = builtins.toJSON {
      TCP = {
        "443".HTTPS = true;
        "${toString intakeTailnetPort}".HTTPS = true;
      };
      Web = {
        # Public via Funnel: only this prefix exists on :443, so anything
        # else (/, /healthz, a guessed path) is a tailscale 404.
        "\${TS_CERT_DOMAIN}:443".Handlers."/p/${ph.podcast-feed-token}/".Path = "/public";
        # Tailnet only: the intake.
        "\${TS_CERT_DOMAIN}:${toString intakeTailnetPort}".Handlers."/".Proxy = "http://host.docker.internal:${toString port}";
      };
      # SECURITY: a deliberate exception to the tailnet-only rule. Overcast
      # fetches feeds and audio from its own servers, so the feed must be
      # reachable from the internet. Exposed: feed.xml and the episode MP3s
      # under /p/<podcast-feed-token>/ on this node's :443, nothing else.
      # The intake (:8444) and Kokoro are not on Funnel. The token is the
      # only access control (Overcast cannot send credentials), so it lives
      # in sops; rotating it changes the feed URL. Funnel is enabled on this
      # dedicated node only, never on nixos-infra's own node or another
      # service's sidecar, and the ACL grants the funnel attribute to
      # tag:podcast alone (docs/PODCAST.md).
      AllowFunnel."\${TS_CERT_DOMAIN}:443" = true;
    };
  };

  users.users.podcast = {
    isSystemUser = true;
    group = "podcast";
  };
  users.groups.podcast = {};

  systemd.services.podcast = {
    description = "Read-later podcast: intake, TTS worker and feed";
    wantedBy = ["multi-user.target"];
    after = ["network-online.target"];
    wants = ["network-online.target"];
    path = [pkgs.ffmpeg-headless];
    environment = {
      PODCAST_STATE_DIR = stateDir;
      PODCAST_PORT = toString port;
      KOKORO_URL = "http://127.0.0.1:${toString kokoroPort}";
      PODCAST_VOICE = voice;
      PODCAST_PUBLIC_BASE = publicBase;
      PODCAST_RETENTION_DAYS = toString retentionDays;
      PODCAST_COVER = "${cover}";
      PYTHONUNBUFFERED = "1";
    };
    startLimitBurst = 5;
    startLimitIntervalSec = 60;
    serviceConfig = {
      # A fixed user rather than DynamicUser: ts-podcast bind-mounts
      # public/, and DynamicUser keeps state behind a /var/lib/private
      # symlink that docker would trip over by creating the path itself.
      User = "podcast";
      Group = "podcast";
      StateDirectory = "podcast";
      ExecStart = "${pyEnv}/bin/python3 ${app}/server.py";
      # Read by systemd as root before dropping privileges.
      EnvironmentFile = config.sops.templates.podcast-env.path;
      Restart = "always";
      RestartSec = "5s";
      # Same set as hn-summaries.nix: it only talks HTTP(S) and runs ffmpeg.
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ProtectKernelTunables = true;
      ProtectControlGroups = true;
      RestrictNamespaces = true;
      LockPersonality = true;
      RestrictAddressFamilies = ["AF_INET" "AF_INET6"];
    };
  };

  # ts-podcast reaches the intake over Docker's bridge, which the firewall
  # does not trust (tailscale0 only). Docker's private range, this port
  # only; the LAN stays blocked. Same rule as gatus.nix.
  networking.firewall.extraCommands = ''
    iptables -A nixos-fw -s 172.16.0.0/12 -p tcp --dport ${toString port} -j nixos-fw-accept
  '';

  majordouble.composeStacks.podcast = {
    composeFile = ../../../stacks/podcast/docker-compose.yml;
    stateDir = "/srv/podcast";
    envFile = config.sops.templates.podcast-compose-env.path;
  };
  # public/ must exist, owned by podcast, before docker bind-mounts it;
  # otherwise docker creates it as root and the worker cannot write there.
  systemd.services.compose-podcast.preStart = ''
    install -d -o podcast -g podcast -m 0755 ${stateDir} ${stateDir}/public
  '';

  # Hermes: one tool, allowlisted. See podcast/mcp_server.py for why this is
  # an MCP tool and not a SKILL.md.
  majordouble.mcpServers.podcast = {
    description = "Hermes tool: queue an article for the read-later podcast";
    command = "${mcpEnv}/bin/python3";
    args = ["${./podcast/mcp_server.py}"];
    environmentFile = config.sops.templates.podcast-mcp-env.path;
    readWritePaths = []; # writes nowhere; it only POSTs to the intake
  };
  # VM-local MCP servers start before the gateway, or hermes parks them
  # after three failed connects (docs/hermes/runtime.md).
  systemd.services.hermes-agent = {
    after = ["mcp-podcast.service"];
    wants = ["mcp-podcast.service"];
  };
  services.hermes-agent.mcpServers.podcast = {
    url = "http://127.0.0.1:${toString mcpPort}/mcp/";
    tools.include = ["podcast_this"];
  };

  # Through the tailnet name and :8444, so DNS, the sidecar's TLS, the
  # intake and Kokoro ([BODY].ok is Kokoro's /health) are polled together.
  # The public feed is not polled: that would put its token in the store.
  services.gatus.settings.endpoints = [
    {
      group = "nixos-infra";
      name = "podcast";
      url = "https://podcast.jaguar-duckbill.ts.net:${toString intakeTailnetPort}/healthz";
      interval = "60s";
      client.timeout = "45s";
      conditions = ["[STATUS] == 200" "[BODY].ok == true"];
      alerts = [{type = "ntfy";}];
    }
  ];
}
