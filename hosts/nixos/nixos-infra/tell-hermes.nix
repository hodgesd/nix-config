# "Tell Hermes": say it to the Apple Watch or iPhone, Hermes runs it and the
# watch speaks the answer. Shortcut steps and test script:
# docs/hermes/tell-hermes.md. Idea from Talk Python #567.
#
#   Shortcut --HTTPS--> ts-tell (tailnet sidecar, tell.jaguar-duckbill.ts.net)
#     --> tell-hermes (native, :8650, bearer token)
#     --> Hermes API server (127.0.0.1:8642, session "tell-hermes")
#   Slow turn: the Shortcut gets "On it..." and the answer follows over
#   Telegram via Hermes's webhook platform (127.0.0.1:8644, deliver_only).
#
# What is built in and what is not: Hermes ships the API server (auth,
# persistent sessions, approvals, toolsets) and the webhook platform (direct
# delivery to the Telegram home channel). tell-hermes/tell_hermes.py is the
# small remainder they lack: a 20-second answer-or-hand-off timer, the
# request log with the spoken text, and plain-text replies. It also keeps
# Hermes's full API (jobs, sessions, per-request provider override) on
# loopback: the tailnet only ever sees POST /tell.
#
# Same shape as gatus.nix: a native service behind a sidecar, so the sidecar
# reaches it over Docker's bridge (firewall rule below) via
# host.docker.internal (sidecars.nix). No Funnel anywhere: serve.json has no
# AllowFunnel, and nothing here is reachable from the internet.
#
# Secrets (sops, secrets/nixos-infra.yaml; create each with
# `openssl rand -hex 32`, never reuse one for the other):
#   tell-hermes-token     the Shortcut's bearer token
#   tell-hermes-internal  adapter <-> Hermes on loopback: it is Hermes's
#                         API_SERVER_KEY and the HMAC secret of the webhook
#                         route. One value for both because both are the same
#                         trust edge (this adapter), and it never leaves the VM.
#
# Disable: remove ./tell-hermes.nix from default.nix imports and the ts-tell
# service from stacks/homelab/docker-compose.yml, deploy. Then delete
# /srv/homelab/ts-tell (the sidecar's tailnet identity), remove the `tell`
# node in the Tailscale admin console, and the two sops entries.
{
  config,
  pkgs,
  ...
}: let
  apiPort = 8642; # Hermes API server
  webhookPort = 8644; # Hermes webhook platform
  adapterPort = 8650; # tell_hermes.py
in {
  sops.secrets = {
    # restartUnits: a rotated token must reach the running adapter (systemd
    # restarts on unit change, not on credential-file change).
    tell-hermes-token.restartUnits = ["tell-hermes.service"];
    tell-hermes-internal.restartUnits = ["tell-hermes.service"];
  };

  # Hermes reads these from its dotenv. Rendered from the one internal secret
  # so there is no second copy to drift. restartUnits for the same reason as
  # hermes-env in hermes.nix.
  sops.templates."tell-hermes-hermes.env" = {
    content = ''
      API_SERVER_KEY=${config.sops.placeholder.tell-hermes-internal}
      WEBHOOK_SECRET=${config.sops.placeholder.tell-hermes-internal}
    '';
    restartUnits = ["hermes-agent.service"];
  };
  services.hermes-agent.environmentFiles = [config.sops.templates."tell-hermes-hermes.env".path];

  services.hermes-agent.settings = {
    # SECURITY: both listeners are pinned to loopback. The webhook adapter's
    # default is BOTH address families on every interface, and the Hermes
    # container shares the host network (--network=host), so an unpinned
    # bind would put an agent-driving endpoint on the LAN.
    platforms.api_server = {
      enabled = true;
      host = "127.0.0.1";
      port = apiPort;
    };
    platforms.webhook = {
      enabled = true;
      host = "127.0.0.1";
      port = webhookPort;
      # The secret is WEBHOOK_SECRET from the env file above, not written here
      # (this repo is public).
      routes.tell-hermes-reply = {
        # Late answers to Telegram's home channel, no LLM call. Needs the DM
        # to have been made the home channel once (`/sethome` in Telegram).
        deliver = "telegram";
        deliver_only = true;
        # So replying to the message in Telegram carries the context.
        mirror_to_session = true;
        prompt = "Re: {heard}\n\n{reply}";
      };
    };

    # SECURITY: a voice command follows the same rules as a typed one, so the
    # API-server surface gets exactly the Telegram toolset (hermes.nix, Phase
    # 0.5 gate 1): no terminal, no file tool, no browser. The upstream default
    # for this surface (hermes-api-server) is the FULL toolset including the
    # shell. MCP servers (vault, Apple, Fastmail) still apply as on Telegram.
    platform_toolsets.api_server = ["messaging" "todo" "vision"];

    # SECURITY: an API-server turn has no human to approve a dangerous
    # command, so it is refused outright instead of waiting out the approval
    # timeout. "deny" is already upstream's default; pinned so a future
    # default change cannot silently turn voice into auto-approve. Stricter
    # than typed (Telegram can approve); nothing here loosens a gate.
    approvals.unattended_mode = "deny";
  };

  systemd.services.tell-hermes = {
    description = "Tell Hermes: voice endpoint in front of Hermes";
    wantedBy = ["multi-user.target"];
    # Ordering only, not a dependency: while Hermes restarts the adapter
    # answers 502 "Hermes didn't answer." rather than going down with it.
    after = ["hermes-agent.service"];
    serviceConfig = {
      # -I: isolated mode, ignores PYTHON* env and the cwd/script dir on sys.path.
      ExecStart = "${pkgs.python3}/bin/python3 -I ${./tell-hermes/tell_hermes.py}";
      # Secrets arrive as files in $CREDENTIALS_DIRECTORY (root reads them
      # from /run/secrets; the unprivileged service user never needs access).
      LoadCredential = [
        "token:${config.sops.secrets.tell-hermes-token.path}"
        "internal:${config.sops.secrets.tell-hermes-internal.path}"
      ];
      SyslogIdentifier = "tell-hermes";
      Restart = "always";
      RestartSec = 5;
      # Contained: it only needs to accept TCP and make loopback TCP calls.
      DynamicUser = true;
      NoNewPrivileges = true;
      CapabilityBoundingSet = "";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictAddressFamilies = ["AF_INET" "AF_INET6"];
      RestrictNamespaces = true;
      LockPersonality = true;
      SystemCallFilter = ["@system-service" "~@privileged" "~@resources"];
    };
  };

  # ts-tell reaches the adapter over the compose project's bridge. The
  # firewall trusts only tailscale0, so without this the proxy gets
  # "connection refused". Scoped to Docker's private range and this one port;
  # the LAN stays blocked (same rule shape as gatus.nix).
  networking.firewall.extraCommands = ''
    iptables -A nixos-fw -s 172.16.0.0/12 -p tcp --dport ${toString adapterPort} -j nixos-fw-accept
  '';

  # ts-tell's serve.json (sidecars.nix) and its Gatus check, which polls
  # GET / (200 "ok", unauthenticated, reveals nothing).
  homelab.sidecars.tell.upstream = "http://host.docker.internal:${toString adapterPort}";
}
