# Stirling PDF — https://pdf.jaguar-duckbill.ts.net
#
# Self-hosted PDF toolbox: merge/split/rotate, compress, convert (to and
# from Office formats and images), OCR, redact, sign, watermark, page
# tools, form filling. Files are processed in memory and not retained
# after the response. Added 2026-09-09 (queued 2026-09-06).
#
# Shape: same as changedetection.nix — a container in stacks/homelab
# (stirlingtools/stirling-pdf, standard variant, digest-pinned) sharing
# the ts-pdf sidecar's network namespace. Nothing binds on the host and
# the firewall is untouched: the app is reachable only through the
# sidecar's tailnet name. Login is switched OFF in the compose file
# because the tailnet is the authentication boundary (the 2.x image
# ships with login ON and a default admin/stirling password — without
# the override that default would sit on the tailnet).
#
# This module only owns the sidecar's serve.json, generated here like
# ts-status's and ts-changes's rather than hand-made on the VM.
# Everything else lives in stacks/homelab/docker-compose.yml.
#
# State: /srv/homelab/stirling-pdf (tessdata, configs, logs, pipeline).
# Nothing precious lives there — the app is stateless by design and the
# directory is recreated from defaults on first start — but it is under
# /srv/homelab so backup.nix mirrors it anyway.
#
# Editing serve.json content below needs `docker restart ts-pdf`
# afterwards: compose does not recreate a container for a bind mount's
# contents (same as ts-status / ts-changes).
#
# Disable: remove ./stirling-pdf.nix from default.nix imports, the
# ts-pdf / stirling-pdf services from stacks/homelab/docker-compose.yml
# and the Gatus endpoint in gatus.nix, then deploy (--remove-orphans
# removes the containers). State to delete afterwards:
# /srv/homelab/stirling-pdf and /srv/homelab/ts-pdf (the sidecar's
# tailnet identity — also remove the `pdf` node in the admin console).
{...}: {
  # Both stanzas are required (see NIXOS-INFRA.md gotchas): TCP.443.HTTPS
  # terminates TLS with the tailnet cert, Web proxies to the app, which is
  # on loopback because it shares the sidecar's namespace.
  environment.etc."ts-pdf/serve.json".text = builtins.toJSON {
    TCP."443".HTTPS = true;
    Web."\${TS_CERT_DOMAIN}:443".Handlers."/".Proxy = "http://127.0.0.1:8080";
  };
}
