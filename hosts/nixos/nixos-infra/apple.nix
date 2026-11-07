# Phase 4: hermes ↔ Apple bridge wiring (VM side).
#
# The bridge lives on the mini (hosts/darwin/mini/apple-mcp/server.py)
# behind tailscale serve :8322; reachability is the second mini hole in
# hermes-egress.nix. Calendar writes are the "Derrick" calendar only
# (create; edit without attendees/recurrence; no delete — 2026-11-07);
# reminder writes are Inbox-only, #hermes-marked — all enforced in the
# server, mirrored here as defense-in-depth. Token handling identical to
# vault.nix: ''${APPLE_MCP_TOKEN} placeholder, expanded from the
# hermes-env dotenv at connect time, never in the store.
#
# Disable: remove this file from the host imports + deploy.
# Revoke: rotate apple-mcp-token in both secrets.
{...}: {
  services.hermes-agent.mcpServers.apple = {
    url = "https://mini.jaguar-duckbill.ts.net:8322/mcp/";
    headers.Authorization = "Bearer \${APPLE_MCP_TOKEN}";
    tools.include = [
      "list_events"
      # Calendar writes: drop these two lines + deploy to go back to
      # read-only (VM side alone is enough).
      "create_event"
      "update_event"
      "list_reminders"
      "create_reminder"
      "move_reminder"
      "snooze_reminder"
      "complete_reminder"
    ];
  };
}
