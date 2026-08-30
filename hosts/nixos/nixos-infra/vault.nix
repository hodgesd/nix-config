# Phase 1: hermes ↔ Obsidian vault wiring (VM side).
#
# The server itself lives on the Mac mini
# (hosts/darwin/mini/vault-mcp/server.py) behind tailscale serve; this
# file only teaches hermes about it. Reachability is the single
# mini:8321 hole in hermes-egress.nix.
#
# The bearer token stays out of the nix store: the header carries a
# literal ''${VAULT_MCP_TOKEN} placeholder in the rendered config.yaml,
# which hermes expands at connect time from its dotenv (the sops
# hermes-env blob — this is hermes's own client credential to the
# bridge, exactly the "url + bearer per server" shape runtime.md
# prescribes; the mini holds the matching copy in secrets/mini.yaml).
#
# Disable: remove this file from the host imports (and optionally the
# egress line) + deploy. Revoke: rotate vault-mcp-token in both secrets.
{...}: {
  services.hermes-agent.mcpServers.vault = {
    url = "https://mini.jaguar-duckbill.ts.net:8321/mcp/";
    headers.Authorization = "Bearer \${VAULT_MCP_TOKEN}";
    tools.include = [
      "append_inbox"
      "create_daily_note"
      "read_note"
      "search_notes"
      "list_notes"
    ];
  };
}
