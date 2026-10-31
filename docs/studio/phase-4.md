# Phase 4 — monitoring studio from nixos-infra

**Status: config written 2026-10-31, PENDING `just deploy` from a Mac.**

## The goal, and why this phase exists

Studio is now load-bearing and **completely silent when it breaks.**
Three separate failures happened in one evening (docs/studio/phase-2.md)
and every one of them looked identical from outside: a timeout that
somebody happened to notice. The box was up, SSH worked, one daemon was
healthy, and nothing said a word.

So the goal is not "add a status page". It is to make the difference
between *box down* and *not serving* visible without logging in, because
that distinction is the first question every one of those incidents
raised and answering it by hand took ten minutes each time.

Direction of monitoring is deliberate and must not drift: **nixos-infra
watches studio. Studio watches nothing.** Studio is compute only; putting
monitoring on it would make the thing being watched responsible for
reporting its own death.

## What was added

`hosts/nixos/nixos-infra/gatus.nix`, a `studio` group with two checks,
using the file's existing `icmp` / `http` helpers and its existing ntfy
alerting. **No new alerting infrastructure, no new secrets, no new
service.**

| Check | Question it answers | Threshold |
|---|---|---|
| `icmp` → `100.126.144.70` | is the machine alive? | 5 failures (~5 min) |
| `http` → `studio.jaguar-duckbill.ts.net:11434/api/version` | is Ollama serving? | 3 failures (~3 min) |

The thresholds are staggered on purpose. On a real outage the HTTP check
pages first and the ping follows, so **which checks are red is itself the
diagnosis**:

| ping | ollama | Meaning |
|---|---|---|
| green | green | fine |
| green | red | the exact failure mode hit three times — box up, not serving |
| red | red | box down, power cut, or tailnet gone |
| red | green | impossible in practice; suspect the monitor |

Two details that would otherwise be rediscovered the hard way:

- **The URL must stay the MagicDNS name.** Ollama validates the HTTP
  Host header and answers 403 to anything it does not recognise, so
  polling `http://100.126.144.70:11434` would page continuously on a
  perfectly healthy box. Same root cause as the 403s in phase-3.md.
- **Plain HTTP, not HTTPS.** There is no `tailscale serve` in front of
  Ollama precisely because the proxy rewrites Host. The tailnet is
  WireGuard-encrypted end to end, the same argument the Home Assistant
  check in that file already makes.

`/api/version` is the cheapest route Ollama has: no model load, no RAM
held. `len([BODY].version) > 0` proves Ollama answered with its own JSON
rather than something else returning 200 in its place.

## What is NOT monitored, stated plainly

**Inference.** There are four distinct health states and this phase
covers the first three:

1. box up — ping
2. API answering — `/api/version`
3. models present — *not checked*
4. inference actually producing tokens — *not checked*

A real-inference probe was considered and **skipped**. It would mean a
periodic `/api/chat` with `max_tokens=1`, which loads a model and then
holds 18–21 GB resident for the whole of `OLLAMA_KEEP_ALIVE = 30m`. At
any sane interval that keeps a model permanently loaded and interacts
badly with `OLLAMA_MAX_LOADED_MODELS = 2`, evicting whatever real work
had warmed. The plan's own principle applies — when a choice trades
simplicity for another nine of availability, take simplicity.

The consequence, so nobody assumes otherwise: **a green board means
Ollama is answering, not that it can generate.** If that gap ever
matters, the right fix is a tiny dedicated model rather than probing the
production ones.

Also unmonitored, by design: if nixos-infra itself dies, studio stops
being watched. That is covered one level up — `healthchecks.nix` is the
off-site dead-man for the VM, so you learn the VM died and can infer
that studio is unwatched. Gatus cannot report its own host's death; see
the comment at the top of gatus.nix.

## Deploy

From a Mac (this cannot be driven from the t3-code VM — both the
Tailscale-SSH and `root@` paths need interactive auth there):

```bash
just deploy-check     # dry-activate, shows what would change
just deploy
```

## How to verify

1. `https://status.jaguar-duckbill.ts.net` shows a **studio** group with
   `ping` and `ollama`, both green.
2. The failure test — stop Ollama for real and watch exactly one check
   flip:

   ```bash
   # on studio. NOTE: it is a SYSTEM daemon, not a user agent, so the
   # gui/$(id -u) form does not apply.
   sudo launchctl bootout system/org.nixos.ollama
   ```

   `KeepAlive` means `kill` is useless here — the process returns in
   seconds. `bootout` removes the job.

   Expect within ~3 minutes: `ollama` red, `ping` **still green**, one
   ntfy notification on the `gatus` topic.

3. Bring it back and confirm the resolved notice arrives
   (`send-on-resolved = true`, `success-threshold = 2`, so ~2 min):

   ```bash
   sudo launchctl bootstrap system /Library/LaunchDaemons/org.nixos.ollama.plist
   ```

## Maintenance: silencing

There is no per-endpoint mute in this setup, and that is a deliberate
simplification rather than an oversight. For planned work on studio,
either accept the pages (two checks, one topic, ~3 min of noise) or
comment the studio block out of gatus.nix and deploy — which is also the
one-line disable.

Do **not** silence by stopping Gatus: it watches six other machines and
services, and a Gatus restart also resets the easy-afd heartbeat window
(see the long comment on `external-endpoints` in gatus.nix).

## How to disable

Remove the two `studio` entries from the `endpoints` list in
`hosts/nixos/nixos-infra/gatus.nix` and deploy. Nothing else was added —
no secrets, no units, no firewall rules — so there is no other state to
clean up.

## Manual test script (5 items)

1. Status page shows the `studio` group, both checks green.
2. `sudo launchctl bootout system/org.nixos.ollama` on studio →
   within ~3 min `ollama` is red, `ping` is green, ntfy fires once.
3. `sudo launchctl bootstrap system /Library/LaunchDaemons/org.nixos.ollama.plist`
   → resolved notice within ~2 min.
4. Pull studio's power (or `sudo shutdown -h now`) → **both** checks go
   red. This is the state that should look different from item 2, and
   confirms the two checks are independent.
5. Curl the 100.x address directly from nixos-infra and confirm it 403s
   — proof that the MagicDNS-name requirement in the config comment is
   real and not superstition.
