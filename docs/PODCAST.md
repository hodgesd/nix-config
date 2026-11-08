# Read-later podcast

Built 2026-11-06. Module `hosts/nixos/nixos-infra/podcast.nix`, code in
`hosts/nixos/nixos-infra/podcast/`, containers in `stacks/podcast/`.

Send an article URL (or pasted text) from the iPhone's Share Sheet, by
telling Hermes "podcast this <url>", or by tagging an Obsidian inbox note
`#listen`. A few minutes later it is an episode in
a private podcast feed in Overcast, read by Kokoro in a voice that sounds
like a person reading the article, not a screen reader reading the page.
The idea is from Talk Python #567 (Jeff Triplett's Hermes setup).

## How it works

```
Shortcut ──https://podcast-intake.jaguar-duckbill.ts.net/enqueue─┐  (tailnet only, bearer)
Hermes ── podcast_this (mcp-podcast, 127.0.0.1:9105) ── 127.0.0.1:8095 ─┤
mini podcast-listen (Inbox #listen, every 15 min) ──── same as Shortcut ─┤
                                                                         ▼
                  podcast.service (native): SQLite queue → fetch → trafilatura
                  → speech.py cleanup → Kokoro (127.0.0.1:8880, one request
                  per paragraph) → ffmpeg concat → MP3 → public/feed.xml
                                                                         ▼
Overcast ◀── Funnel ── https://podcast.jaguar-duckbill.ts.net/p/<token>/feed.xml
```

- **Intake** returns 202 at once; the Shortcut never waits for TTS.
- **Ready alert**: after the MP3 and feed are published, the worker calls
  Overcast's [ping API](https://overcast.fm/podcasterinfo) (free, no
  account), so Overcast refreshes the feed at once instead of on its next
  poll. The alert is Overcast's own: in Overcast, open *Read Later* →
  settings → turn on **Notifications**. It fires only once Overcast has the
  episode, so "ready" is true when it arrives. A failed ping is logged and
  the episode still appears on Overcast's next poll.
- **Extraction**: trafilatura. A page that yields under 200 words
  (paywall, login wall, not an article) fails the job with the reason
  kept in the `jobs` table; nothing broken is published.
- **Cleanup for speech** (`speech.py`, deterministic, no LLM): link text
  kept and URLs dropped; footnote markers, reference sections, images and
  captions, share/subscribe/next-article furniture, nav crumbs and
  link-only lists dropped; every code block becomes "Code sample omitted.";
  inline code read as words; headings become a short spoken line with
  pauses around it; press releases stop at `-end-`; an intro line
  ("Title. By Author, from Site.") opens each episode.
- **Kokoro fixes**: only what Kokoro-FastAPI's own normalizer still got
  wrong in the three test articles, checked by running that normalizer on
  them: `v0.17.0`, `Mach .75`, `FIPS 140-3` (read as a range), `--flags`,
  `i.e.`/`e.g.`, dotted names like `pyproject.toml` and `.venv`, `VS Code`.
- **Synthesis**: a paragraph per Kokoro request (long ones split at
  sentence ends, 1,200 characters max), 0.6 s of silence after a paragraph
  and 1 s after a heading, joined by ffmpeg into mono 64 kbps MP3 with ID3
  tags.
- **Feed**: RSS 2.0 with iTunes tags (stable `guid` = job id, `enclosure`
  with byte length, `itunes:duration`, description with the source URL,
  `itunes:block` so Apple's directory never lists it). Episodes and their
  MP3s are deleted after 30 days.

## Exposure

| What | Where | Reachable from |
|---|---|---|
| feed.xml + MP3s | `ts-podcast` :443, path `/p/<podcast-feed-token>/` only | **Internet (Funnel)** |
| Intake (HTTPS) | `ts-podcast-intake` :443 (homelab stack) → `host.docker.internal:8095` | Tailnet |
| Intake (HTTP) | nixos-infra :8095 | Tailnet (firewall trusts tailscale0 only) |
| Kokoro | 127.0.0.1:8880 on the VM | The VM only |
| Hermes tool | 127.0.0.1:9105 on the VM | The VM only |

Funnel is on for one node, `podcast`, a sidecar that exists only for this
stack; never nixos-infra's own node or another sidecar. The ACL grants the
`funnel` attribute to `tag:podcast` and nothing else.

The intake has its own node, `podcast-intake`, because a Funnel node's
name is in public DNS: `podcast.jaguar-duckbill.ts.net` also resolves to
Tailscale's Funnel relays. The intake first lived on `podcast` :8444, and
the iPhone resolved that name to a relay, which drops every port but
Funnel's, so the Shortcut timed out (2026-11-07). A node without Funnel
has no public record; its name resolves only to the tailnet address.
Keep tailnet-only services off the `podcast` node.

The fetcher refuses any URL that resolves to a non-public address
(loopback, LAN, tailnet, link-local), re-checked on every redirect, so a
queued URL can't read a homelab page aloud into the public feed.

## Resources

nixos-infra on 2026-11-06: 4 vCPUs (`cpu: host`; AVX, AVX2 and FMA
present), 11 GiB RAM, 16 GB free on `/`.

- **Speed**: a 58.2 s clip (171 words, `af_heart`) took 24.0 s and 23.6 s
  to generate, **2.4–2.5× real time**. A 20-minute article is ready in
  about 8 minutes.
- **Memory**: Kokoro peaks at 1.7 GiB.
- **Disk**: the Kokoro image is about 3 GB; MP3s are about 0.5 MB a
  minute and pruned at 30 days.

The VM does not need more resources. More vCPUs would only make episodes
arrive sooner. Kokoro runs at `cpu_shares: 256`, so during synthesis it
yields to AdGuard, Hermes and the rest.

## Artwork

`podcast/cover.svg` (a bookmark with a play button). The build renders it to
a 3000 px PNG; podcast.service copies it to `public/cover.png` at start and
names it in the feed's `<image>` and `<itunes:image>`. Edit the SVG and
deploy to change it; Overcast picks it up on its next fetch.

## Voice

`af_heart`: the only grade-A voice in hexgrad's Kokoro-82M `VOICES.md`
(`af_bella` is A-, the male voices C+ and below), Kokoro-FastAPI's
default, and the voice the speed above was measured with. Change it in
`podcast.nix` (`voice = …`).

## One-time setup (done 2026-11-06)

Recorded so it can be redone after a rebuild or a key rotation.

1. **Tailscale ACL** (admin console → Access controls). The policy is
   allow-all, so only the tag and its Funnel attribute were added, next to
   the existing `tag:cmy` entries:

   ```jsonc
   "tagOwners": {
     "tag:podcast": ["group:admin"],
   },
   "nodeAttrs": [
     // Funnel for the podcast sidecar only. Never widen this to tag:homelab.
     {"target": ["tag:podcast"], "attr": ["funnel"]},
   ],
   ```

   If the policy ever stops being allow-all, the phones, Macs (the mini's
   `#listen` watcher) and nixos-infra (Gatus, `tag:homelab`) need tcp/443
   on the `podcast-intake` node.

2. **Auth key** (admin console → Settings → Keys → Generate auth key):
   not reusable, not ephemeral, tag `tag:podcast`, 7-day expiry (it only
   has to outlast the wait until the first deploy). It is used once; the node's identity then lives in
   `/srv/podcast/ts-podcast/state`. It must not be the homelab key: that
   key's tags are what every other sidecar carries.

3. **Secrets**, on the Mac in this repo (zsh; nothing is echoed or kept
   in history):

   ```zsh
   sops set secrets/nixos-infra.yaml '["podcast-intake-token"]' "\"$(openssl rand -hex 32)\""
   sops set secrets/nixos-infra.yaml '["podcast-feed-token"]' "\"$(openssl rand -hex 32)\""
   read -rs 'K?tag:podcast auth key: '; echo; printf '"%s"' "$K" | sops set --value-stdin secrets/nixos-infra.yaml '["podcast-ts-authkey"]'; unset K
   ```

   And the same intake token for the mini's `#listen` watcher:

   ```zsh
   sops set secrets/mini.yaml '["podcast-intake-token"]' \
     "\"$(sops -d --extract '["podcast-intake-token"]' secrets/nixos-infra.yaml)\""
   ```

4. `just deploy-check`, then `just deploy`. Switch the mini (`just` on the
   mini) to start the `#listen` watcher.

5. **Overcast**: + → Add URL →
   `https://podcast.jaguar-duckbill.ts.net/p/<podcast-feed-token>/feed.xml`
   (read the token with
   `sops -d --extract '["podcast-feed-token"]' secrets/nixos-infra.yaml`).

### Rotating a token

Set the new value as in step 3 and deploy, plus:

- **podcast-feed-token**: on nixos-infra, `docker stop ts-podcast`
  *before* the deploy and `docker start ts-podcast` after it. The sidecar
  reads serve.json only at start, so a running one keeps the old
  `/p/<old-token>/` path on Funnel, and it would serve the rewritten
  feed.xml with the new token in it. The deploy doesn't start it again
  (the compose file is unchanged). Check that the old feed URL answers
  404 and the new one 200, then re-add the new URL in Overcast.
- **podcast-intake-token**: copy it into `secrets/mini.yaml` again and
  switch the mini, and paste it into the Shortcut's Text action (step 2
  below). Both keep their own copy.

## iOS Shortcut: "Podcast This"

The phone must be on the tailnet (Tailscale app connected). The Shortcut
only forwards what it was shared; the intake decides what it is. A URL on
the first line is fetched even when the submitted text continues with page
content. A URL with up to 40 other words (news apps share "Headline
https://…") is also fetched. Anything else is read as pasted text, titled
from its first paragraph when that is short, else its opening words. Kept
this small on purpose: a Shortcut has no history or diff,
and the first, 10-step version lost three actions without a trace
(2026-11-08; most likely an iCloud sync conflict or a stray Delete). The logic
lives in `speech.link_capture` and `speech.from_text`, under test.

Build it in Shortcuts → +, actions in this order (as built on iOS 26):

1. **Receive** from **Share Sheet**: add any action first and the grey
   *Receive* block appears on top. Tap *Nowhere* → *Share Sheet*, tap the
   input types and leave only *URLs* and *Text* on. If there's no input:
   *Ask For* → *Text*.
2. **Text**: paste the value of `podcast-intake-token` (on the mbp:
   `sops -d --extract '["podcast-intake-token"]' secrets/nixos-infra.yaml | pbcopy`,
   then `pbcopy < /dev/null` once done). The token lives only here.
3. **Set Variable**: *Token* to *Text*.
4. **Get Contents of URL**: `https://podcast-intake.jaguar-duckbill.ts.net/enqueue`.
   Expand it: Method *POST*; Headers: `Authorization` = `Bearer `, a space,
   then the *Token* variable (a blue bubble, not typed); no other header
   rows; Request Body *JSON*, one field: `text` (Text) = *Shortcut Input*.
5. **Show Notification**: *Contents of URL*. That is the intake's reply,
   `{"id": …, "status": "queued"}` on success. Get Contents of URL does not
   stop on an HTTP error, so a fixed "Queued" message would also show for
   a 401 (bad token) or a 400 (empty body).

**Show in Share Sheet** (under ⓘ in the bottom bar) is switched on by
choosing *Share Sheet* in step 1. From Safari or a news app: Share →
Podcast This. The reply appears within a second; the episode follows a few
minutes later. Edit it on one device and let iCloud sync before opening it
on another. After any edit, run it once and check for `"queued"`.

## Hermes

`podcast_this(url | text, title)` is an MCP tool (`podcast/mcp_server.py`),
allowlisted alone in `services.hermes-agent.mcpServers.podcast`. Typed or
spoken through Tell Hermes, "podcast this <url>" calls it. It holds the
intake token itself; Hermes sees only the loopback URL.

Why not a `SKILL.md`: Hermes skills live in `/var/lib/hermes/.hermes/skills`
(bundled ones plus one the agent wrote itself; none are declared in this
repo). A skill is instructions the agent carries out with its own tools,
and since Phase 0.5 the Telegram surface has no terminal, web or skills
toolsets. An MCP tool is how every other integration reaches Hermes, and it
works from both Telegram and the webhook.

## Obsidian `#listen`

The vault lives on the mini; nixos-infra only sees it through Hermes's
vault bridge. So the mini does the watching: `podcast-listen`
(`hosts/darwin/mini/podcast-listen.nix`, a user LaunchAgent like the
bridge) scans `Inbox/*.md` every 15 minutes and queues each note tagged
`#listen` (inline or in frontmatter `tags`) once:

- a link capture (a URL plus at most 40 other words) goes as the URL;
- anything longer goes as pasted text, titled with the note's name.

It never writes to the vault. What it has sent is in
`~/Library/Application Support/podcast-listen/sent.json` (to resend a
note, remove its entry and keep the JSON valid: no comma left after the
last entry, or the watcher stops at that file every run); its log is `~/Library/Logs/podcast-listen.log`. A failed send is
retried on the next run. It runs only while the mini's GUI session is up,
same as the bridges.

## Verify

```bash
curl -s https://podcast-intake.jaguar-duckbill.ts.net/healthz        # tailnet: {"ok": true, "kokoro": true, ...}
ssh root@100.98.163.36 journalctl -u podcast -n 20                    # queued / done / failed lines
ssh root@100.98.163.36 'sqlite3 -readonly /var/lib/podcast/podcast.db \
  "select status, coalesce(ep_title, url), reason from jobs order by created desc limit 10"'
```

From outside the tailnet (phone on LTE with Tailscale off): the feed URL
answers 200; `https://podcast.jaguar-duckbill.ts.net/` and `…/healthz` answer
404; `podcast-intake.jaguar-duckbill.ts.net` doesn't resolve and
`nixos-infra-1:8095` doesn't connect.

Gatus: group `nixos-infra`, endpoint `podcast` (`podcast-intake`'s
`/healthz`, which is
only `ok` when Kokoro answers too).

## Tests

```bash
cd hosts/nixos/nixos-infra/podcast
uv run pytest        # speech cleanup on the three saved pages in tests/fixtures
uv run ruff check . && uv run ruff format --check .
```

## Disable

Remove `./podcast-listen.nix` from the mini's imports and switch it. Remove
`./podcast.nix` from the imports in
`hosts/nixos/nixos-infra/default.nix`, delete the `ts-podcast-intake`
service from `stacks/homelab/docker-compose.yml` (its serve.json comes from
podcast.nix) and `just deploy`, then on the VM
`docker compose --project-directory /srv/podcast down` (this also takes the
Funnel down). Afterwards delete `/var/lib/podcast`, `/srv/podcast` and
`/srv/homelab/ts-podcast-intake`, remove the `podcast` and `podcast-intake`
nodes in the admin console, the `tag:podcast` ACL
entries and the `podcast-*` sops keys in both secrets files.

Emergency, Funnel only: `docker stop ts-podcast` on the VM.

## Credential inventory (names and scopes only)

| Name | Used by | Scope |
|---|---|---|
| `podcast-intake-token` | podcast.service (checks it); mcp-podcast, the mini's podcast-listen (`secrets/mini.yaml`) and the Shortcut (a Text action) send it | Queue a job. Nothing else. |
| `podcast-feed-token` | podcast.service (writes feed URLs), ts-podcast serve.json (the Funnel path), Overcast (in the URL) | Read the feed and the MP3s. Rotating it changes the feed URL. |
| `podcast-ts-authkey` | ts-podcast, first login only | Join the tailnet as `tag:podcast`, one use, 1-day expiry. |

## Manual test script

1. Safari on the iPhone (Tailscale on) → Share → Podcast This on a
   long-form article. The notification shows `"status": "queued"` at once;
   `journalctl -u podcast` shows `queued` and, minutes later, `done … Nx
   real time`.
2. In Overcast, pull to refresh the Read Later feed: the episode is there,
   the intro says title, author and site, links are read as their words,
   no URLs or "code block" noise.
3. Tell Hermes on Telegram "podcast this <a URL>". It replies "Queued
   (job …)", and `hermes-audit` shows one `mcp__podcast__podcast_this` call.
4. Queue a paywalled article. No episode appears;
   `sqlite3 … "select reason from jobs where status='failed'"` says why.
5. Phone on LTE with Tailscale off: the feed URL loads in Safari,
   `https://podcast.jaguar-duckbill.ts.net/` is a 404, and
   `https://podcast-intake.jaguar-duckbill.ts.net/healthz` does not resolve.
