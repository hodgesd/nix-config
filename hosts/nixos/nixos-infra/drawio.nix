# draw.io (diagrams.net) — https://drawio.jaguar-duckbill.ts.net
#
# Self-hosted diagram editor: flowcharts, network/architecture diagrams,
# UML, floor plans; opens and saves .drawio/.png/.svg files locally in the
# browser (Device storage), no account needed. Added 2026-09-09.
#
# Shape: same as stirling-pdf.nix — a container in stacks/homelab
# (jgraph/drawio, digest-pinned) sharing the ts-drawio sidecar's network
# namespace. Nothing binds on the host and the firewall is untouched: the
# app is reachable only through the sidecar's tailnet name. There is no
# login to turn off — the app has none; the tailnet is the boundary.
#
# This module only owns the sidecar's serve.json, generated here like
# ts-status's / ts-changes's / ts-pdf's rather than hand-made on the VM.
# Everything else lives in stacks/homelab/docker-compose.yml.
#
# State: none. draw.io is a static web app served by Tomcat; diagrams
# live wherever the browser saves them (local file, or a cloud provider
# the user connects from the app). The only directory on the VM is the
# sidecar's tailnet identity, /srv/homelab/ts-drawio.
#
# Editing serve.json content below needs `docker restart ts-drawio`
# afterwards: compose does not recreate a container for a bind mount's
# contents (same as ts-status / ts-changes / ts-pdf).
#
# Disable: remove ./drawio.nix from default.nix imports, the
# ts-drawio / drawio services from stacks/homelab/docker-compose.yml and
# the Gatus endpoint in gatus.nix, then deploy (--remove-orphans removes
# the containers). State to delete afterwards: /srv/homelab/ts-drawio
# (the sidecar's tailnet identity — also remove the `drawio` node in the
# admin console).
{...}: {
  # Both stanzas are required (see NIXOS-INFRA.md gotchas): TCP.443.HTTPS
  # terminates TLS with the tailnet cert, Web proxies to the app, which is
  # on loopback because it shares the sidecar's namespace. Tomcat's own
  # 8443 (self-signed) is simply never reached.
  environment.etc."ts-drawio/serve.json".text = builtins.toJSON {
    TCP."443".HTTPS = true;
    Web."\${TS_CERT_DOMAIN}:443".Handlers."/".Proxy = "http://127.0.0.1:8080";
  };
}
