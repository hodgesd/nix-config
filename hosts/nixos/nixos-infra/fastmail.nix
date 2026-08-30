# Phase 3a: Fastmail read-only triage.
#
# The first untrusted-content integration: email bodies enter Hermes's
# sessions. The layered posture that makes that acceptable (see
# docs/hermes/phase-3a.md): read-only token (account layer), a server
# containing no write code (tool layer), metadata-first tool shape,
# policy.md mail rules (flag instruction-bearing mail, never obey), and
# a Telegram surface with no shell/web/send — an injected email has no
# exfiltration channel.
#
# Credential separation: the token is consumed ONLY by this unit;
# hermes-env gains nothing and hermes sees only the loopback URL.
#
# Disable: remove ./fastmail.nix from the host imports + deploy.
# Revoke: delete the hermes-ro token at Fastmail (individually
# revocable — the reason it's a dedicated token).
{
  config,
  pkgs,
  ...
}: let
  pythonEnv = pkgs.python3.withPackages (ps: [ps.fastmcp ps.httpx]);
in {
  sops.secrets.fastmail-hermes-ro-token.restartUnits = ["mcp-fastmail.service"];

  majordouble.mcpServers.fastmail = {
    description = "Fastmail read-only JMAP MCP server (metadata-first)";
    command = "${pythonEnv}/bin/python3";
    args = ["${./fastmail-mcp/server.py}"];
    environmentFile = config.sops.secrets.fastmail-hermes-ro-token.path;
    readWritePaths = []; # read-only integration: writes nowhere
  };

  # The parking lesson: VM-local MCP servers start before the gateway.
  systemd.services.hermes-agent = {
    after = ["mcp-fastmail.service"];
    wants = ["mcp-fastmail.service"];
  };

  services.hermes-agent.mcpServers.fastmail = {
    url = "http://127.0.0.1:9102/mcp/";
    tools.include = [
      "list_mailboxes"
      "recent_emails"
      "search_emails"
      "get_email"
    ];
  };
}
