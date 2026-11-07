# Tell Hermes — voice from Apple Watch or iPhone

Say "Tell Hermes" to the watch or phone, speak a request, and Hermes runs it
as if you had typed it into Telegram. The watch speaks back a short answer.
Idea from Talk Python #567 (~54:00–55:10). One HTTPS call over Tailscale. No
SMS, iMessage, Telegram bot or Funnel.

Config: `hosts/nixos/nixos-infra/tell-hermes.nix`, adapter
`hosts/nixos/nixos-infra/tell-hermes/tell_hermes.py`, sidecar `ts-tell` in
`stacks/homelab/docker-compose.yml`.

## What was built, and why this shape

Hermes (pinned rev 3cf2eb1c) already has an OpenAI-compatible **API server**
(bearer auth, persistent sessions, approvals, toolsets) and a **webhook
platform** (direct delivery to Telegram). Those do the real work. They do
not do three things the feature needs, so a ~150-line stdlib adapter sits in
front:

| Need | Built in? |
| --- | --- |
| Bearer auth, one persistent session, approval gating | Yes (API server) |
| Answer within ~20 s or hand off | No: no timer, no hand-off mode |
| Late answer to Telegram | Yes via webhook `deliver_only`, but nothing triggers it for an API turn (`send_message` is not an agent tool at this rev) |
| Request log containing the spoken text | No: aiohttp logs path/status/time only |

The adapter also keeps Hermes's full API (jobs, sessions, per-request provider
override) on loopback: the tailnet only ever sees `POST /tell`.

```
Shortcut → https://tell.jaguar-duckbill.ts.net/tell   (ts-tell sidecar, tailnet only)
  → tell-hermes :8650     bearer token #1: tell-hermes-token
  → Hermes API  127.0.0.1:8642   session "tell-hermes", key #2: tell-hermes-internal
  slow turn → reply "On it, I'll message you when it's done."
            → later: signed POST to 127.0.0.1:8644 → Telegram home channel
```

- **Same rules as typed.** The voice surface gets exactly the Telegram
  toolset (`messaging`, `todo`, `vision`: no shell, no file tool). Upstream's
  default for it would be the full toolset including the shell. MCP servers
  (vault, Apple, Fastmail) still apply, as on Telegram.
- **Dangerous commands are refused, not approved.** An API-server turn has no
  human to ask, so `approvals.unattended_mode = "deny"` (upstream's default,
  pinned) blocks them instantly. Stricter than typed; nothing is loosened.
- **Reply** is plain text, one or two sentences. Waits 20 s (`TELL_REPLY_WAIT`).
- **Session**: one fixed session id, `tell-hermes`, so "and also…" works.
  Follow-ups after a Telegram hand-off also carry context
  (`mirror_to_session`).

## Before the first deploy (you; this VM has no age key)

The build fails until both secrets exist in the ciphertext (sops-nix checks
the key names at build time), so `just deploy` aborts before touching anything.

1. `openssl rand -hex 32` twice. One is the Shortcut token, one is internal.
   Do not reuse one for the other, and do not paste either into chat or the repo.
2. `sops secrets/nixos-infra.yaml`, add two string keys:
   `tell-hermes-token` and `tell-hermes-internal`. Commit to the PR branch.
3. Put the token in the Shortcut only (below). Save it in your password manager.
4. In Telegram, DM the bot and send `/sethome` once if you have not already:
   late answers go to the home channel.
5. Check `TS_AUTHKEY` in `homelab-env` is still valid and reusable
   (Tailscale admin → Settings → Keys). `ts-tell` registers a new node `tell`.
6. From the Mac: `just deploy-check`, then `just deploy`. **This restarts
   hermes-agent** (new env file and settings), so pick a quiet moment.

The `just` recipes are macOS-only; nothing here was deployed from the VM.

## Verify after deploy

From a tailnet machine, token in `$TELL_TOKEN` (set it without echoing it).

```sh
# valid token → Hermes's reply
curl -sS -m 40 -X POST https://tell.jaguar-duckbill.ts.net/tell -H "Authorization: Bearer $TELL_TOKEN" -d '{"text":"What is two plus two?"}'
# missing token → 401, wrong token → 401
curl -sS -o /dev/null -w '%{http_code}\n' -X POST https://tell.jaguar-duckbill.ts.net/tell -d '{"text":"hi"}' && curl -sS -o /dev/null -w '%{http_code}\n' -X POST https://tell.jaguar-duckbill.ts.net/tell -H 'Authorization: Bearer wrong' -d '{"text":"hi"}'
# off the tailnet: Tailscale off on a phone on cellular; the name must not connect
curl -sS -m 10 https://tell.jaguar-duckbill.ts.net/
```

Log (spoken text and timing, never the token):
`journalctl -t tell-hermes -n 30` on nixos-infra, e.g.
`heard: 'what is two plus two'` / `replied in 4.1s` / `handed off after 20.0s`
/ `finished after 63.2s, sent to Telegram` / `rejected: missing or wrong token`.

## The Shortcut

Create a shortcut named exactly **Tell Hermes** (the name is the voice trigger).
Actions, in order:

1. **Dictate Text**. Language English; Stop Listening: After Pause.
2. **Get Contents of URL**. Tap Show More, then:
   - URL: `https://tell.jaguar-duckbill.ts.net/tell`
   - Method: **POST**
   - Headers: add `Authorization` = `Bearer ` followed by your token
   - Request Body: **JSON**; add a **Text** field named `text`, value = the
     **Dictated Text** variable
3. **Get Text from Input**, input = **Contents of URL**. The reply is already
   plain text, so there is no JSON to unpack; this just makes the hand-off to
   the next step explicit.
4. **Speak Text** with that text (Wait Until Finished on). Use **Show Result**
   instead for a silent reply.

The token lives in this Shortcut only.

**Apple Watch:** open the shortcut, tap the (i) details button, turn on
**Show on Apple Watch**. Raise the wrist and say "Tell Hermes" (Siri finds it
by name), or tap it in the Shortcuts app on the watch.

**Not verified (no watch or phone available when this was written):**
- *Whether the watch can reach the tailnet.* watchOS has no Tailscale client.
  The shortcut works only if the watch's request reaches `tell.…ts.net`
  through the iPhone's Tailscale VPN. Test it (below). If the watch cannot
  connect, run the shortcut from the iPhone (Siri or Action Button) instead;
  do not widen the endpoint to fix it.
- *Running with the iPhone locked.* Needs Tailscale connected on the phone
  (set VPN On Demand or keep it connected) and, for "Hey Siri" on the phone,
  Siri allowed on the lock screen. Test with the phone locked and record
  what is needed.

## Disable

Remove `./tell-hermes.nix` from `hosts/nixos/nixos-infra/default.nix` and the
`ts-tell` service from `stacks/homelab/docker-compose.yml`, then
`just deploy`. Afterwards delete `/srv/homelab/ts-tell`, remove the `tell`
node in the Tailscale admin console, and delete the two sops keys.

## Credential inventory (names and scopes only)

| Name | Where | Used for |
| --- | --- | --- |
| `tell-hermes-token` | sops, the Shortcut | Bearer token for `POST /tell`; grants one chat turn on the Telegram toolset |
| `tell-hermes-internal` | sops only | Hermes `API_SERVER_KEY` and webhook HMAC secret; loopback; never leaves the VM |
| `TS_AUTHKEY` | existing `homelab-env` | Registers the `tell` tailnet node |

Rotate by changing the sops value and deploying; both units restart.

## Manual test script

1. Valid token → the curl returns one or two plain sentences, no markdown.
2. No token and a wrong token → both 401; the log has `rejected`, no token.
3. Ask something that needs several tool calls (for example, "summarise my
   unread Fastmail from today") → "On it, I'll message you when it's done."
   within ~20 s, then the answer arrives in Telegram.
4. Ask "and what was the first one about?" right after a quick answer →
   it knows what "the first one" means (single session).
5. Ask it to run a shell command or delete something → refused (no shell on
   this surface; dangerous commands blocked), and the audit log shows no
   terminal call.
