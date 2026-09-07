# changedetection.io — https://changes.jaguar-duckbill.ts.net
#
# Self-hosted web-page change monitor: watches URLs (price/restock pages,
# release and advisory pages, appointment slots, JSON APIs, PDFs, sites
# without RSS), diffs them, and notifies via Apprise — here the ntfy on
# this VM. Added 2026-09-06.
#
# Shape: a container in stacks/homelab (ghcr.io/dgtlmoon/changedetection.io,
# digest-pinned) sharing the ts-changes sidecar's network namespace, plus
# a sockpuppetbrowser container for the Chrome fetcher. Deliberately NOT
# the nixpkgs services.changedetection-io module: 25.11 ships 0.51.3,
# which predates the 0.55.6 SSRF fix, and its playwrightSupport pulls an
# unpinned, upstream-deprecated browserless/chrome image. The compose
# route gets the current release and lands the datastore under
# /srv/homelab, so backup.nix already mirrors it nightly.
#
# This module only owns the sidecar's serve.json, generated here like
# ts-status's rather than hand-made on the VM. Everything else lives in
# stacks/homelab/docker-compose.yml. Nothing binds on the host and the
# firewall is untouched: the sidecar sits on the tailnet, and Chrome is
# reachable only over the compose network.
#
# UI state (password, notification URL, watches, history) is in
# /srv/homelab/changedetection — that directory is the whole restore.
#
# Editing serve.json content below needs `docker restart ts-changes`
# afterwards: compose does not recreate a container for a bind mount's
# contents (same as ts-status).
#
# Disable: remove ./changedetection.nix from default.nix imports and the
# ts-changes / changedetection / sockpuppetbrowser services from
# stacks/homelab/docker-compose.yml, deploy (--remove-orphans removes the
# containers). State to delete afterwards: /srv/homelab/changedetection
# and /srv/homelab/ts-changes (the sidecar's tailnet identity — also
# remove the `changes` node in the admin console).
{...}: {
  # Both stanzas are required (see NIXOS-INFRA.md gotchas): TCP.443.HTTPS
  # terminates TLS with the tailnet cert, Web proxies to the app, which is
  # on loopback because it shares the sidecar's namespace.
  environment.etc."ts-changes/serve.json".text = builtins.toJSON {
    TCP."443".HTTPS = true;
    Web."\${TS_CERT_DOMAIN}:443".Handlers."/".Proxy = "http://127.0.0.1:5000";
  };
}
