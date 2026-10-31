# Phase 0 — studio: registry, flake output, CI

**Status: DONE 2026-10-30.** The host exists and evaluates; no services, no
activation, no hardware involved. Phase 1 (headless baseline) is next and
also needs no hardware.

## What was built

| File | Change |
|---|---|
| `lib/machines.nix` | `studio` entry: darwin, `m5-ultra`, desktop, `primaryUse = "server"` |
| `flake.nix` | `studio = libx.mkDarwin {hostname = "studio";}` |
| `hosts/darwin/studio/default.nix` | **new** — purpose header, FileVault recovery-ladder comment, `power` block (restart after power failure/freeze, never sleep, display 15 min) |
| `.github/workflows/eval.yaml` | matrix entry `darwinConfigurations.studio.system` |
| `.github/workflows/build.yaml` | `studio` added to the darwin (macos-latest) build matrix → closure lands in Cachix |
| `README.md` | machines-table row |

`primaryUse = "server"` rather than a new `"ai"` role is the load-bearing
decision: it reuses the three existing `primaryUse != "server"` gates
instead of adding a registry field no module reads. Verified empirically,
not assumed (see below). Studio-only behavior should branch on
`machine.hostname == "studio"`.

## How to verify

```bash
# Host evaluates (this is what CI runs):
nix eval --raw ".#darwinConfigurations.studio.system.drvPath"

# No other host moved — mbp must be byte-identical to before this phase:
nix eval --raw ".#darwinConfigurations.mbp.system.drvPath"
# => /nix/store/sjmhfpyyzkzrf3a3wh9finqqz3c3k0ca-darwin-system-26.05.c3e90c8.drv

# The three server gates actually apply to studio (studio / mbp):
nix eval --raw ".#darwinConfigurations.studio.config.homebrew.masApps" \
  --apply 'x: toString (builtins.length (builtins.attrNames x))'      # 0 / 30
nix eval ".#darwinConfigurations.studio.config.homebrew.casks" \
  --apply 'x: builtins.elem "t3-code" (map (c: c.name) x)'            # false / true
nix eval ".#darwinConfigurations.studio.config.environment.systemPackages" \
  --apply 'x: builtins.any (p: builtins.match ".*herdr.*" (p.pname or "") != null) x'
                                                                      # false / true
```

Results on 2026-10-30: studio drvPath
`/nix/store/311fcbv2za5kq0mh5spvrvnj8gs9ddrk-darwin-system-26.05.c3e90c8.drv`;
mbp unchanged; masApps 0 vs 30; `t3-code` cask absent (matches `mini`);
herdr absent.

NB: `config.homebrew.casks` elements are **submodules**, not strings —
nix-darwin coerces them (`{name = "..."; brewfileLine = ...; ...}`). A naive
`builtins.elem "t3-code" casks` returns `false` for every host and looks
like a passing test. Match on `.name`.

## How to disable / revert

Entirely inert until a Mac actually named `studio` runs
`darwin-rebuild switch --flake .#studio`, so there is nothing to turn off.
To remove the host: delete the `lib/machines.nix` entry, the `flake.nix`
output, `hosts/darwin/studio/`, both CI matrix entries and the README row.
Nothing else references it.

## Manual test script (5 items)

1. `nix eval --raw ".#darwinConfigurations.studio.system.drvPath"` → prints a
   `.drv` path, no error.
2. `nix eval --raw ".#darwinConfigurations.mbp.system.drvPath"` → matches the
   hash recorded above (your Mac's closure did not change).
3. Push the branch and confirm GitHub Actions **Eval 🔍** runs a `studio` job
   and it passes (plus the existing five).
4. Confirm **Build 🍎** has a `studio` job (triggers on PR) and that it
   pushes to Cachix, so the Studio's first `darwin-rebuild` is mostly
   downloads rather than an M5 compiling for an hour.
5. `grep studio README.md` → the machines table lists it. RAM shows 96GB;
   storage and core counts are `—` on purpose, to be filled in Phase 2 from
   the machine itself.

## Notes for later phases

- **Formatting trap.** The documented bare `nix fmt` fails on this nix
  (2.34.8): with no path argument alejandra reads stdin and dies with
  `unexpected end of file`. `nix fmt .` works but reformats **six
  pre-existing files** — including
  `hosts/nixos/nixos-infra/hardware-configuration.nix`, which CLAUDE.md
  says to keep byte-for-byte as generated. There is latent alejandra drift
  in the tree (likely an alejandra version bump since those files were last
  touched). Format explicit paths only:
  `nix fmt lib/machines.nix flake.nix hosts/darwin/studio/default.nix`.
  Worth a separate cleanup commit someday, deliberately not mixed in here.
- **Unresolved, by design:** storage size and CPU/GPU core counts (Phase 2),
  the `iogpu.wired_limit_mb=83500` daemon and Remote Login (Phase 1), and
  the ledger items that are yours to decide (oMLX on laptops, cask role
  split, public access, UPS).
- `t3-code` is missing from the README machines table (pre-existing, not
  related to this phase). Left alone to keep the diff to one change.
