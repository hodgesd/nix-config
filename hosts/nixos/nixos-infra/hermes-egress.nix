# Phase 0.5 gate 2: default-deny egress for the hermes agent, keyed to its
# UID. The upstream module hardcodes --network=host (verified at the pinned
# rev and at HEAD — no option exists), so per-container network policy is
# off the table without patching upstream. Owner-match is the sturdier
# lever: every agent process (gateway, its shells, hooks) runs as the
# hermes user on the host netns, so `-m owner --uid-owner hermes` scopes
# exactly the agent workload and nothing else on this shared-duty VM.
#
# Model: "no east-west, https-only north-south".
#  - loopback + established: resolved-stub/local services + return traffic.
#  - port 53 anywhere: NetworkManager points resolv.conf at the LAN
#    resolver, whose address is DHCP-assigned — pinning it would break on
#    lease changes. KNOWN RESIDUAL: DNS is an exfil channel; the named-
#    domain egress proxy (phase-0.5 follow-up) closes it.
#  - reject RFC1918 / CGNAT (tailnet) / link-local BEFORE the 443 allow:
#    kills LAN/NAS/hypervisor/tailnet lateral movement, including HTTPS
#    to the UniFi console or NAS.
#  - allow tcp/443 to what remains (public internet): Telegram long-poll
#    and the Anthropic API keep working with no domain-pinning fragility.
#  - log-then-reject everything else (rate-limited; grep the journal for
#    "hermes-egress-drop").
#
# Inbound is NOT covered: owner-match only works for locally-generated
# output, and tailscale0 is a trusted interface — the agent UID could
# still bind a tailnet-visible listener. Documented residual (tailnet-only
# exposure); revisit with the Tailscale-sidecar question.
#
# Disable: remove this file from the host imports and redeploy.
{lib, ...}: let
  # DNS first (see header), then east-west rejects, then public https.
  rules4 = [
    "-o lo -j ACCEPT"
    "-m state --state ESTABLISHED,RELATED -j ACCEPT"
    "-p udp --dport 53 -j ACCEPT"
    "-p tcp --dport 53 -j ACCEPT"
    # Phase 1: the ONE deliberate east-west hole — the mini's vault bridge
    # (tailscale serve, bearer-token'd). One host, one port, before the
    # CGNAT reject below. Every future integration adds its own line here
    # rather than widening anything.
    "-d 100.122.244.86 -p tcp --dport 8321 -j ACCEPT"
    # Phase 4: the mini's Apple bridge (Reminders/Calendar).
    "-d 100.122.244.86 -p tcp --dport 8322 -j ACCEPT"
    "-d 10.0.0.0/8 -j REJECT"
    "-d 172.16.0.0/12 -j REJECT"
    "-d 192.168.0.0/16 -j REJECT"
    "-d 100.64.0.0/10 -j REJECT"
    "-d 169.254.0.0/16 -j REJECT"
    "-p tcp --dport 443 -j ACCEPT"
    "-m limit --limit 6/minute -j LOG --log-prefix \"hermes-egress-drop: \""
    "-j REJECT"
  ];
  rules6 = [
    "-o lo -j ACCEPT"
    "-m state --state ESTABLISHED,RELATED -j ACCEPT"
    "-p udp --dport 53 -j ACCEPT"
    "-p tcp --dport 53 -j ACCEPT"
    "-d fc00::/7 -j REJECT"
    "-d fe80::/10 -j REJECT"
    "-p tcp --dport 443 -j ACCEPT"
    "-m limit --limit 6/minute -j LOG --log-prefix \"hermes-egress-drop: \""
    "-j REJECT"
  ];
  mkChain = ipt: rules: ''
    ${ipt} -w -D OUTPUT -m owner --uid-owner hermes -j hermes-egress 2>/dev/null || true
    ${ipt} -w -F hermes-egress 2>/dev/null || true
    ${ipt} -w -X hermes-egress 2>/dev/null || true
    ${ipt} -w -N hermes-egress
    ${lib.concatMapStringsSep "\n" (r: "${ipt} -w -A hermes-egress ${r}") rules}
    ${ipt} -w -I OUTPUT -m owner --uid-owner hermes -j hermes-egress
  '';
  rmChain = ipt: ''
    ${ipt} -w -D OUTPUT -m owner --uid-owner hermes -j hermes-egress 2>/dev/null || true
    ${ipt} -w -F hermes-egress 2>/dev/null || true
    ${ipt} -w -X hermes-egress 2>/dev/null || true
  '';
in {
  networking.firewall.extraCommands =
    (mkChain "iptables" rules4) + (mkChain "ip6tables" rules6);
  networking.firewall.extraStopCommands =
    (rmChain "iptables") + (rmChain "ip6tables");
}
