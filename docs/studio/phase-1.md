# Phase 1 — studio: headless-server baseline

**Status: DONE 2026-10-30.** Still no AI services and no hardware required;
everything here is config that takes effect at the Studio's first
`darwin-rebuild switch` (Phase 2).

## What was built

All in `hosts/darwin/studio/default.nix`.

| Thing | Mechanism |
|---|---|
| macOS never self-installs OS updates | `system.defaults.SoftwareUpdate.AutomaticallyInstallMacOSUpdates = false` |
| App Store apps never self-update | `CustomUserPreferences."com.apple.commerce".AutoUpdate = lib.mkForce false` |
| GPU may wire ~85% of RAM | `launchd.daemons.gpu-wired-limit` → `sysctl iogpu.wired_limit_mb=83500` at boot |
| Model/cache dirs never backed up or indexed | `system.activationScripts.extraActivation` → `mkdir` + `.metadata_never_index` + `tmutil addexclusion` for `~/.ollama` and `~/.cache/huggingface` |
| Remote Login drift is noticed | non-fatal warning in the same activation hook |

### Why the update posture looks small

`hosts/common/darwin/defaults/security.nix` already sets
`AutomaticCheckEnabled`, `AutomaticDownload` and `CriticalUpdateInstall` on
in the **user** domain for every Mac, and studio inherits them on purpose:
checking and staging never reboot on their own, and `CriticalUpdateInstall`
covers security responses, which are data rather than OS updates. Only two
things needed changing — the OS-update installer (off) and App Store
auto-update (off, because a server shouldn't have a binary swapped under a
running service; same reasoning as `homebrew.nix`'s `upgrade = false`).

**Do not** re-declare the inherited keys in `CustomSystemPreferences`. A
second copy in the system domain shadows the fleet setting and makes the
posture ambiguous. The `mkForce` on `AutoUpdate` is required because
`security.nix` sets a plain `true`, not a `mkDefault`.

## What could NOT be made declarative

Confirmed by introspecting nix-darwin 26.05's option set, not assumed:

| Setting | Why not | Status |
|---|---|---|
| Remote Login (SSH) | `services.openssh`'s activation script only runs `ssh-keygen` for host keys — enabling it does not turn Remote Login on. `systemsetup -setremotelogin on` needs Full Disk Access for the calling process, which an activation script run over SSH lacks. | **done by hand 2026-10-30** |
| Screen Sharing | no option; same TCC problem | done by hand, optional |
| "Start up when power is connected" = Always | `power.*` exposes only `restartAfterFreeze`, `restartAfterPowerFailure`, `sleep` | **done by hand 2026-10-30** |
| Login Items approval ("Allow in the Background") | macOS 13+ holds login-item approval in `backgroundtaskmanagementd`'s private database; not writable declaratively. Tailscale reports *"start at login could not be set"* until it is granted: System Settings > General > Login Items & Extensions. | **optional**, see phase-2.md |
| Auto-login (`/etc/kcpassword`) | `system.defaults.loginwindow.autoLoginUser` sets the username but macOS also needs the obfuscated password in `/etc/kcpassword`, which nix-darwin does not write. The declarative alternative is storing the login password in sops to be written back out in a trivially reversible format — worse. | **required 2026-10-31**, see phase-2.md |

Remote Login being manual is the uncomfortable one: it is how a
keyboard-less box is administered at all, and it carries the authorized
key that lets this repo be driven against studio over the tailnet. Hence
the activation warning: if it ever drifts off, every rebuild says so in
yellow, instead of the fact surfacing when you need in. The warning is
deliberately non-fatal; a rebuild should not fail over it.

**Superseded 2026-10-30:** this section originally justified Remote Login
as the prerequisite for FileVault pre-boot SSH unlock. FileVault was
subsequently turned off on studio (see the plan's CONTEXT block), so that
recovery path no longer applies — the machine boots to loginwindow
unattended instead. Remote Login is still load-bearing for the reason
above.

## How to verify (after the first switch)

```bash
# GPU ceiling actually applied at boot (0 means "unset, macOS default"):
sysctl iogpu.wired_limit_mb            # => 83500
sudo launchctl print system/org.nixos.gpu-wired-limit | head

# Update posture:
defaults read /Library/Preferences/com.apple.SoftwareUpdate \
  AutomaticallyInstallMacOSUpdates     # => 0
defaults read com.apple.commerce AutoUpdate   # => 0

# Exclusions (both must exist and be excluded):
tmutil isexcluded ~/.ollama ~/.cache/huggingface
ls -a ~/.ollama | grep metadata_never_index
```

## How to disable

- **GPU ceiling** — comment out the `launchd.daemons.gpu-wired-limit` block
  and rebuild. The value returns to the macOS default on the next boot (or
  immediately with `sudo sysctl iogpu.wired_limit_mb=0`).
- **Update posture** — delete the two `system.defaults` lines; studio falls
  back to the fleet defaults from `security.nix`.
- **Exclusions / warning** — remove the
  `system.activationScripts.extraActivation.text` block. Already-set
  exclusions persist (they are an xattr); undo with
  `tmutil removeexclusion <path>`.

## Manual test script (5 items)

1. After the Phase 2 switch: `sysctl iogpu.wired_limit_mb` → `83500`. If it
   reads `0`, the daemon did not run — check
   `/var/log/gpu-wired-limit.log`.
2. Reboot (`sudo fdesetup authrestart`), then re-run the same command. It
   must still be `83500` — this is the whole reason it's a daemon and not a
   one-shot.
3. `tmutil isexcluded ~/.ollama` → excluded. Confirms the `mkdir`-first
   ordering worked on a machine where the directory didn't exist.
4. Turn Remote Login **off** in System Settings, run `darwin-rebuild switch`,
   and confirm the yellow warning appears and the rebuild still **succeeds**.
   Turn it back on. (This is the one test worth actually doing — it proves
   the recovery-path guard works.)
5. System Settings → General → Software Update → confirm it still checks and
   offers updates, but "Install macOS updates" is off.

## Notes for later phases

- `extraActivation`, `extraPostActivation` and `extraUserPostActivation`
  were all empty; this phase uses `extraActivation`. Hook contents are
  inlined into the root activation runner (verified), so writing to one is
  not a silent no-op — but check before picking a new one.
- Phase 3/3b should extend the existing `for d in …` list rather than
  adding a second exclusion mechanism, e.g. for oMLX's
  `--paged-ssd-cache-dir`.
- mbp's drvPath moved during this phase for an unrelated reason: the
  `qpdf`/`poppler-utils` commit that arrived with main. Verified by
  evaluating mbp with and without the Phase 1 diff — byte-identical
  (`5qha6i23g7m233afza3l720dkm7m6g7p`). Re-baseline before using it as a
  regression check in a later phase.
