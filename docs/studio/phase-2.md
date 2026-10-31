# Phase 2 — studio: hardware bootstrap and the unattended-reboot test

**Status: two reboot tests run 2026-10-31, both failed, two independent
causes found and fixed.** Re-test pending.

The whole FileVault-off design (phase-1.md, phase-3.md) rests on one
claim: *this box comes back serving after an unattended reboot, with
nobody logged in.* Testing it found two unrelated faults, and the first
test could not see past the first one.

```bash
sudo reboot
# then, WITHOUT logging in, from another tailnet node:
curl -s http://studio.jaguar-duckbill.ts.net:11434/api/version
```

## Fault 1 — Tailscale was not running

First reboot: `tailscale status` from the control plane showed
`studio … offline, last seen 1m ago`. The machine itself was healthy —
diagnosed over the LAN, which is the only reason any of this was
visible:

| Probe | Result |
|---|---|
| `ping 192.168.1.198` | 0.6ms, 0% loss |
| `ssh hodgesd@192.168.1.198` | works |
| `uptime` | `up 0:02, 0 users` |
| `ifconfig \| grep utun` | **no interfaces** |
| `Tailscale status` / `ip` | **exit 124 (timeout)** |

With no login session the Tailscale CLI cannot reach its backend, so
that state was **undiagnosable from the box** — which is what made the
first conclusion wrong (see below). Enabling auto-login produced a
session (`who` → `hodgesd console`), the CLI started answering, and the
actual state was:

```
Tailscale status  → "Tailscale is stopped."
WantRunning: false
LoggedOut:   false
```

Authenticated, but deliberately disconnected, and that preference
persists across reboots. `tailscale up` fixed it immediately and the
node came back on the tailnet.

**The first draft of this file concluded "Tailscale's macOS GUI app
cannot establish the tunnel without a login session."** That was wrong,
or at least unproven: no `utun` and a hanging CLI are equally consistent
with `WantRunning = false`, and once a session existed the app did come
up. The honest statement is narrower: *without a session the CLI backend
is unreachable, so the app's state cannot be inspected* — and the app was
in a stopped state for reasons not established.

Auto-login is kept regardless (`system.defaults.loginwindow.autoLoginUser`).
It is what made the box diagnosable, and the GUI app is session-bound
for other things. It is available only because FileVault is off; it costs
an unlocked desktop, acceptable on a box whose threat model already
accepts physical access, and **must not be copied to the mini**. It also
needs a manual step — see phase-1.md's not-expressible list — because
macOS wants the obfuscated password in `/etc/kcpassword`, which
nix-darwin does not write.

## Fault 2 — the daemon lost a race with the /nix volume, and died for good

This is the more important one, and it was hidden behind fault 1. Even
after Tailscale came up, Ollama stayed dead:

```
launchctl print system/org.nixos.ollama
  state = spawn scheduled
  active count = 0
```

It never respawned — watched for 88s across four samples, and no new
line appeared in `~/Library/Logs/ollama.log` for the entire uptime. The
system log said why:

```
launchd: Missing executable detected. Job: 'org.nixos.ollama'
         Executable: '/nix/store/…-ollama-0.34.3-mlx/bin/ollama'
```

The executable was plainly there — running it by hand as the service user
worked perfectly, resolved MagicDNS, and bound
`100.126.144.70`. The cause is boot ordering:

```
/dev/disk3s7 on /nix (apfs, local, nosuid, journaled, noatime, nobrowse)
org.nixos.darwin-store   program = /usr/sbin/diskutil   runs = 1, exit 0
```

`/nix` is a **separate APFS volume**, mounted by a launchd job. A
`RunAtLoad` system daemon whose program lives in the store can start
before that mount completes. And launchd's reaction to a *missing
executable* is to abandon the job — `KeepAlive` does not rescue it,
because KeepAlive restarts processes that ran and exited, not jobs whose
binary was absent at exec time.

So the service was dead for the entire uptime, and would have stayed
dead until a manual `launchctl kickstart` or another reboot that happened
to win the race.

Two things that previously looked like evidence of something else, now
explained:

- `last exit code = 78: EX_CONFIG` was a **stale** record from before the
  reboot, when Ollama really was exiting on a failed bind. It was not
  what was happening after the reboot, and it misled the first diagnosis.
- `launchd.daemons.gpu-wired-limit` survived the same boot
  (`runs = 1, exit 0`, sysctl reads 83500) because its program is
  `/usr/sbin/sysctl` — outside `/nix`. The difference between the two
  daemons is the location of the binary, nothing else.

### The fix

```nix
ProgramArguments = [
  "/bin/sh" "-c"
  "/bin/wait4path ${ollama}/bin/ollama && exec ${ollama}/bin/ollama serve"
];
```

`/bin/sh` and `/bin/wait4path` live outside `/nix`, so launchd can always
exec them. `wait4path` blocks until the store appears; `exec` then
replaces the shell, so launchd supervises the real process and KeepAlive
semantics are unchanged.

**This applies to any daemon on any Mac in this repo whose program lives
in the Nix store** — it is not studio-specific. Studio is just the first
host with an always-on store-resident system daemon, so it is the first
place the race could bite.

## How to verify

```bash
sudo reboot
# WITHOUT touching the machine, from another tailnet node:
tailscale status | grep studio                 # must NOT say offline
curl -s http://studio.jaguar-duckbill.ts.net:11434/api/version
ssh hodgesd@studio 'ollama run qwen3.8:27b-mlx "say hi"'
```

All three with no interaction. And on the box:

```bash
launchctl print system/org.nixos.ollama | grep "state ="   # running, not spawn scheduled
```

If Tailscale is `offline` again, the next move is `tailscaled` as a
system daemon rather than more auto-login tinkering — `tailscale`
1.102.4 is in nixpkgs for aarch64-darwin. Risks recorded: it conflicts
with the installed app, needs an auth key or a new node registration,
uses the unsupported `utun` path on macOS, and may break MagicDNS, which
Ollama binds *by name* (that bind would move to the literal
`100.126.144.70`).

## What this says about Phase 4

Both faults were silent from outside: the box looked fine, one daemon
was healthy, and the only symptom was a timeout someone happened to
notice. Gatus would have reported it within a minute. Phase 4 is not a
nice-to-have.

## Keep this in mind

The LAN path is the recovery mechanism for this host. Remote Login plus a
second route is why these faults were diagnosable at all — phase-1.md
calls Remote Login load-bearing, and this is the incident that proves it.

## Manual test script (5 items)

1. `defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser`
   → `hodgesd`, and `/etc/kcpassword` exists.
2. Reboot untouched; `launchctl print system/org.nixos.ollama` shows
   `state = running`. If it shows `spawn scheduled` with
   `active count = 0`, the store race is back.
3. Same reboot: `tailscale status | grep studio` is not `offline`.
4. Same reboot: the API answers over the tailnet.
5. Same reboot: a generation completes over SSH. This is the bar Phase 3
   claimed and Phase 2 has to actually deliver.
