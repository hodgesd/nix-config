# Tailscale ACL draft — `tag:hermes` (Phase 0)

**Status: draft for you to apply in the admin console**
(<https://login.tailscale.com/admin/acls>). I have no console access — this
file is the proposed diff, with each rule explained. Nothing here changes the
repo or any host.

## One structural caveat first (read before applying)

Hermes runs in a container **with host networking** on nixos-infra, sharing
the VM's tailscale identity. Two consequences:

1. **Tagging means tagging the whole VM.** Tailscale ACL sources are nodes,
   not processes — `tag:hermes` on nixos-infra also covers easy-afd, the
   proxy, the homelab stack, and anything else on that VM. Source-side ACLs
   are therefore *coarse* containment; the fine-grained enforcement stays
   destination-side (the mini bridge's bearer token, the UniFi account's
   read-only role).
2. **Converting a node from user-owned to tagged is a real change.** A tagged
   node stops matching rules that target your user identity — audit any
   existing rules, Tailscale SSH grants, and `tailscale serve` sharing that
   assume `nixos-infra` belongs to `hodgesd@` before applying. If your
   policy is still the default allow-all, the tag is *preparation* (rules
   below add nothing restrictive yet); the payoff comes when you later
   replace the default-allow rule.

## Proposed policy additions (HuJSON — comments are valid in the console)

```jsonc
{
  "tagOwners": {
    // Only admins (you) may apply or transfer this tag.
    "tag:hermes": ["autogroup:admin"],
  },

  "acls": [
    // ── Existing rules stay above this line ──────────────────────────────
    // If you still have the default rule
    //   {"action": "accept", "src": ["*"], "dst": ["*:*"]}
    // the rules below are dormant documentation until you remove it.

    // Phase 4: Hermes → EventKit/vault bridge on the mini.
    // PORT IS A PLACEHOLDER — Phase 4 picks the real one; update then.
    // The bridge additionally requires a bearer token, so network reach
    // alone is not access.
    {"action": "accept", "src": ["tag:hermes"], "dst": ["mini:8321"]},

    // Phase 2: Hermes → UniFi console local API (HTTPS on the gateway).
    // Replace UNIFI-CONSOLE with the console's tailnet name or IP — if the
    // console is NOT on the tailnet, this rule is moot and reachability is
    // plain LAN routing (the host-networking caveat above); the read-only
    // API account is then the only enforcement, which is why it exists.
    {"action": "accept", "src": ["tag:hermes"], "dst": ["UNIFI-CONSOLE:443"]},

    // Deliberately absent: hermes → NAS, hermes → other Macs, hermes → *.
    // New integrations add their own single-port rule in their phase.
  ],
}
```

## How to apply the tag

Admin console → Machines → `nixos-infra` → ⋯ → Edit ACL tags → `tag:hermes`.
(Or declaratively later via `tailscale up --advertise-tags=tag:hermes` on the
VM — that requires the tag to exist in the policy first.)

## Verification

From any tailnet device: `tailscale status` shows `nixos-infra` with
`tag:hermes`. Once the default-allow rule is gone, `tailscale ping` /
`nc -z` from the VM to a non-listed host:port should fail, and to
`mini:8321` should connect (when the Phase 4 bridge exists).

## Rollback

Remove the tag from the machine and delete the two rules — the policy editor
keeps version history, so the previous policy is one click away.
