# Phase 2 — studio: hardware bootstrap and the unattended-reboot test

**Status: test run 2026-10-31 — it FAILED, and the cause is Tailscale,
not anything in this repo.** Fix below.

## The test

The whole FileVault-off design (see phase-1.md, phase-3.md) rests on one
claim: *this box comes back serving after an unattended reboot, with
nobody logged in.* That had never been tested. It is now.

```bash
sudo reboot
# then, WITHOUT logging in at the screen, from another tailnet node:
curl -s http://studio.jaguar-duckbill.ts.net:11434/api/version
```

Result: timeout. `tailscale status` from the control plane showed

```
100.126.144.70  studio  hodgesd@  macOS  offline, last seen 1m ago
```

## What actually failed

The machine was fine. Diagnosed from a VM on the same LAN, which is why
having a second path in mattered:

| Probe | Result |
|---|---|
| `ping 192.168.1.198` | 0.6ms, 0% loss |
| `ssh hodgesd@192.168.1.198` | works |
| `uptime` | `up 0:02, 0 users` — booted, nobody logged in |
| `who` | empty |
| `ifconfig \| grep utun` | **no interfaces at all** |
| `Tailscale status` / `ip` | **exit 124 (timeout)** — CLI backend unreachable |
| `/Applications/Tailscale.app` process | running as `hodgesd`, started at boot |
| system LaunchDaemon/LaunchAgent for tailscale | none |

So Tailscale's macOS **GUI app** launches at boot but cannot establish
the tunnel without a login session: no `utun`, and the CLI hangs because
the backend it talks to lives in the GUI app's session context.

Ollama behaved exactly as designed, which is the one piece of good news:

```
launchctl print system/org.nixos.ollama
  state = spawn scheduled
  last exit code = 78: EX_CONFIG
```

It cannot bind `studio.jaguar-duckbill.ts.net:11434` while tailscaled has
not assigned the address, so it exits and `KeepAlive` +
`ThrottleInterval = 15` retries. It will self-heal the instant Tailscale
comes up. **The Phase 3 daemon choice is correct and needs no change —
only its prerequisite was unmet.** This is precisely the open question
flagged in phase-3.md ("whether Tailscale on macOS comes up without a
GUI login at all. If it doesn't, the tailnet is unreachable after an
unattended reboot no matter how Ollama binds"), now answered: it does
not.

## The fix: auto-login

`system.defaults.loginwindow.autoLoginUser = "hodgesd"`. A GUI session
exists from boot, Tailscale.app connects, Ollama's retry loop succeeds.

This is the fallback the plan designated from the start, and it is
available *because* FileVault is off. What it costs: the desktop sits
unlocked. That is a smaller marginal loss than it sounds here — the
threat model already accepts physical access to this box (FileVault off,
no Apple ID, no personal data, only re-downloadable weights). It is the
wrong choice on the mini and must not be copied there.

**Not fully declarative.** macOS also requires the account password,
obfuscated, in `/etc/kcpassword`; `autoLoginUser` alone preselects the
user without completing the login. Writing kcpassword declaratively
would mean putting the login password in sops to be written back out in
a trivially reversible format — worse than the GUI step. So auto-login
joins the manual list in phase-1.md:

> System Settings → Users & Groups → "Automatically log in as" → hodgesd

The nix option is still declared, so the intent is in git and drift is
visible.

### The alternative, and why it is not the default

Run `tailscaled` from nixpkgs (`tailscale` 1.102.4 is available for
aarch64-darwin) as a system LaunchDaemon. Architecturally this is the
right answer for a headless server: no GUI session, no auto-login, no
unlocked desktop, fully declarative.

It was not chosen now because it carries several risks that are hard to
validate on a box reachable only over LAN SSH:

- It conflicts with the installed Tailscale.app; that would have to go.
- Registration needs an auth key (a new sops secret) or a one-time
  interactive login, and would likely appear as a **new node** unless
  the old one is removed in the admin console.
- `tailscaled` on macOS with `utun` is the unsupported path.
- MagicDNS resolution may not work under it, and Ollama binds *by name*
  — so that bind would have to move to the literal `100.126.144.70`.

The plan's stated principle applies: "When a choice trades simplicity
against another nine of availability, take simplicity and say so."
Auto-login is one option plus one GUI toggle. Revisit `tailscaled` if
auto-login proves flaky.

## What this says about Phase 4

Gatus would have reported this within a minute of the reboot instead of
it being noticed by hand. Phase 4 is no longer just nice to have — the
box has now demonstrated a failure mode that is completely silent from
the outside.

## How to verify the fix

```bash
# after enabling auto-login and switching:
sudo reboot
# WITHOUT touching the machine, from another tailnet node:
tailscale status | grep studio                 # must NOT say offline
curl -s http://studio.jaguar-duckbill.ts.net:11434/api/version
ssh hodgesd@studio 'ollama run qwen3.8:27b-mlx "say hi"'
```

All three must pass with no interaction. If Tailscale still does not
connect, auto-login is not sufficient and `tailscaled` becomes the next
move — not more auto-login tinkering.

## How to disable

Remove `system.defaults.loginwindow.autoLoginUser` and rebuild, then
turn auto-login off in System Settings (the nix option does not own
`/etc/kcpassword`). The box reverts to requiring a login, which means
reverting to LAN-only access after a reboot.

## Keep this in mind

The LAN path is the reason this was diagnosable at all. Remote Login
plus a second network route is the recovery mechanism for this host —
phase-1.md already calls Remote Login load-bearing, and this is the
incident that proves it.

## Manual test script (5 items)

1. `defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser`
   → `hodgesd`.
2. Reboot and do not touch the machine. From another node,
   `tailscale status | grep studio` must not say `offline`.
3. Same reboot: `curl http://studio.jaguar-duckbill.ts.net:11434/api/version`
   returns a version.
4. Same reboot: generate over SSH. This is the acceptance bar Phase 3
   claimed and Phase 2 must actually deliver.
5. `launchctl print system/org.nixos.ollama` → `state = running`, not
   `spawn scheduled`. If it reads `spawn scheduled` with
   `last exit code = 78`, the tunnel is still down.
