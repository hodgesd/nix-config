# Read-later podcast

Built 2026-11-06. Module `hosts/nixos/nixos-infra/podcast.nix`, code in
`hosts/nixos/nixos-infra/podcast/`, containers in `stacks/podcast/`.

Send an article URL (or pasted text) from the iPhone's Share Sheet or by
telling Hermes "podcast this <url>". A few minutes later it is an episode in
a private podcast feed in Overcast, read by Kokoro in a voice that sounds
like a person reading the article, not a screen reader reading the page.
The idea is from Talk Python #567 (Jeff Triplett's Hermes setup).

## How it works

```
Shortcut ──https://podcast.jaguar-duckbill.ts.net:8444/enqueue──┐  (tailnet only, bearer)
Hermes ── podcast_this (mcp-podcast, 127.0.0.1:9105) ── 127.0.0.1:8095 ─┤
                                                                         ▼
                  podcast.service (native): SQLite queue → fetch → trafilatura
                  → speech.py cleanup → Kokoro (127.0.0.1:8880, one request
                  per paragraph) → ffmpeg concat → MP3 → public/feed.xml
                                                                         ▼
Overcast ◀── Funnel ── https://podcast.jaguar-duckbill.ts.net/p/<token>/feed.xml
```

- **Intake** returns 202 at once; the Shortcut never waits for TTS.
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
| Intake (HTTPS) | `ts-podcast` :8444 → `host.docker.internal:8095` | Tailnet |
| Intake (HTTP) | nixos-infra :8095 | Tailnet (firewall trusts tailscale0 only) |
| Kokoro | 127.0.0.1:8880 on the VM | The VM only |
| Hermes tool | 127.0.0.1:9105 on the VM | The VM only |

Funnel is on for one node, `podcast`, a sidecar that exists only for this
stack; never nixos-infra's own node or another sidecar. The ACL grants the
`funnel` attribute to `tag:podcast` and nothing else. Port 8444 cannot be
put on Funnel even by mistake: Funnel only serves 443, 8443 and 10000.

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

## Voice

`af_heart`: the only grade-A voice in hexgrad's Kokoro-82M `VOICES.md`
(`af_bella` is A-, the male voices C+ and below), Kokoro-FastAPI's
default, and the voice the speed above was measured with. Change it in
`podcast.nix` (`voice = …`).

## One-time setup (Derrick)

1. **Tailscale ACL** (admin console → Access controls). Add:

   ```jsonc
   "tagOwners": {
     "tag:podcast": ["autogroup:admin"],
   },
   "nodeAttrs": [
     // Funnel for the podcast sidecar only. Never widen this to tag:homelab.
     {"target": ["tag:podcast"], "attr": ["funnel"]},
   ],
   ```

   If the policy is not allow-all, also let your devices and nixos-infra
   (Gatus) reach the intake:

   ```jsonc
   "grants": [
     {"src": ["autogroup:member"], "dst": ["tag:podcast"], "ip": ["8444"]},
     {"src": ["tag:homelab"], "dst": ["tag:podcast"], "ip": ["8444"]},
   ],
   ```

2. **Auth key** (admin console → Settings → Keys → Generate auth key):
   not reusable, not ephemeral, pre-approved, tag `tag:podcast`, 1-day
   expiry. It is used once; the node's identity then lives in
   `/srv/podcast/ts-podcast/state`. It must not be the homelab key: that
   key's tags are what every other sidecar carries.

3. **Secrets**, on the Mac in this repo:

   ```bash
   sops set secrets/nixos-infra.yaml '["podcast-intake-token"]' "\"$(openssl rand -hex 32)\""
   sops set secrets/nixos-infra.yaml '["podcast-feed-token"]' "\"$(openssl rand -hex 32)\""
   sops secrets/nixos-infra.yaml   # add: podcast-ts-authkey: tskey-auth-…
   ```

4. `just deploy-check`, then `just deploy`.

5. **Overcast**: + → Add URL →
   `https://podcast.jaguar-duckbill.ts.net/p/<podcast-feed-token>/feed.xml`
   (read the token with
   `sops -d --extract '["podcast-feed-token"]' secrets/nixos-infra.yaml`).

## iOS Shortcut: "Podcast This"

The phone must be on the tailnet (Tailscale app connected). Build it in
Shortcuts → +, actions in this order:

1. **Receive** *URLs, Safari web pages and Text* input from *Share Sheet*.
   If there's no input: *Ask For* → *Text*.
2. **Text**: paste the value of `podcast-intake-token`. Tap the action's
   output and rename the variable to `Token`. The token lives only here.
3. **Get URLs from Input**: *Shortcut Input*.
4. **If** *URLs* *has any value*
5. — **Get Item from List**: *First Item* from *URLs*.
6. — **Get Contents of URL**: `https://podcast.jaguar-duckbill.ts.net:8444/enqueue`.
   Expand it: Method *POST*; Headers: `Authorization` = `Bearer ` followed
   by the `Token` variable; Request Body *JSON*, one field: `url` (Text) =
   *Item from List*.
7. **Otherwise**
8. — **Ask for Input**: *Text*, prompt `Title?`.
9. — **Get Contents of URL**: same URL, method and header as step 6;
   Request Body *JSON* with `text` (Text) = *Shortcut Input* and `title`
   (Text) = *Provided Input*.
10. **End If**
11. **Show Notification**: `Queued for the podcast`.

Then in the shortcut's settings (ⓘ) turn on **Show in Share Sheet**. From
Safari: Share → Podcast This. The notification appears within a second;
the episode follows a few minutes later.

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

Not built. The vault lives on the mini, and nixos-infra reaches it only
through Hermes's vault bridge (`vault.nix`, tools `read_note`,
`search_notes`, `list_notes` and three append-only writes). The worker has
no path to it, and inventing a sync was out of scope. Decision pending.

## Verify

```bash
curl -s https://podcast.jaguar-duckbill.ts.net:8444/healthz          # tailnet: {"ok": true, "kokoro": true, ...}
ssh root@100.98.163.36 journalctl -u podcast -n 20                    # queued / done / failed lines
ssh root@100.98.163.36 'sqlite3 -readonly /var/lib/podcast/podcast.db \
  "select status, coalesce(ep_title, url), reason from jobs order by created desc limit 10"'
```

From outside the tailnet (phone on LTE with Tailscale off): the feed URL
answers 200; `https://podcast.jaguar-duckbill.ts.net/` and `…/healthz` answer
404; `:8444` and `nixos-infra-1:8095` don't connect.

Gatus: group `nixos-infra`, endpoint `podcast` (`:8444/healthz`, which is
only `ok` when Kokoro answers too).

## Tests

```bash
cd hosts/nixos/nixos-infra/podcast
uv run pytest        # speech cleanup on the three saved pages in tests/fixtures
uv run ruff check . && uv run ruff format --check .
```

## Disable

Remove `./podcast.nix` from the imports in
`hosts/nixos/nixos-infra/default.nix` and `just deploy`, then on the VM
`docker compose --project-directory /srv/podcast down` (this also takes the
Funnel down). Afterwards delete `/var/lib/podcast` and `/srv/podcast`,
remove the `podcast` node in the admin console, the `tag:podcast` ACL
entries and the three `podcast-*` sops keys.

Emergency, Funnel only: `docker stop ts-podcast` on the VM.

## Credential inventory (names and scopes only)

| Name | Used by | Scope |
|---|---|---|
| `podcast-intake-token` | podcast.service (checks it), mcp-podcast (sends it), the Shortcut (a Text action) | Queue a job. Nothing else. |
| `podcast-feed-token` | podcast.service (writes feed URLs), ts-podcast serve.json (the Funnel path), Overcast (in the URL) | Read the feed and the MP3s. Rotating it changes the feed URL. |
| `podcast-ts-authkey` | ts-podcast, first login only | Join the tailnet as `tag:podcast`, one use, 1-day expiry. |

## Manual test script

1. Safari on the iPhone (Tailscale on) → Share → Podcast This on a
   long-form article. The notification appears at once;
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
   `https://podcast.jaguar-duckbill.ts.net:8444/healthz` does not connect.
