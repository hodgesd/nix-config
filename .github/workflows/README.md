# CI workflows

These workflows verify this config so breakage shows up before `darwin-rebuild switch`.

| Workflow | Trigger | Runner | What it does |
|---|---|---|---|
| `eval.yaml` | every push / PR | Linux (free, fast) | Evaluates all 3 hosts. Catches syntax errors, bad options, module conflicts, per-host metadata branches. No build. |
| `build.yaml` | `flake.lock` change, nightly, manual | macOS | Full `nix build` of all 3 hosts; pushes results to Cachix. |
| `update-flake-lock.yaml` | weekly, manual | Linux | Opens a PR bumping `flake.lock`, gated by the above. |
| `flake-checker.yaml` | every push, nightly | Linux | Audits `flake.lock` health (stale nixpkgs). |
| `renovate.yaml` | weekly, manual | Linux | Self-hosted Renovate: opens one grouped PR bumping the homelab compose images (rules in `/renovate.json`). |

## One-time setup

`build.yaml` needs the Cachix cache and `renovate.yaml` needs a PAT; `eval.yaml` works immediately.

### 1. Create a free Cachix cache

1. Sign in at <https://app.cachix.org> with GitHub (free tier: 5 GB).
2. Create a **public** cache named **`hodgesd-nix-config`**
   (must match the `name:` in `build.yaml` — change both if you pick another name).
3. Generate an **auth token**: cache → Settings → Auth Tokens → create a *push* token.

### 2. Add the token as a repo secret

```bash
gh secret set CACHIX_AUTH_TOKEN   # paste the token when prompted
```

### 3. (Optional) Make local `switch` pull from the cache

Add the cache as a substituter so your Macs download prebuilt paths instead of
recompiling. Put this in `hosts/common/darwin/base.nix` under `nix.settings`
(the public key is shown on the cache's page after you create it):

```nix
nix.settings = {
  substituters = [ "https://hodgesd-nix-config.cachix.org" ];
  trusted-public-keys = [ "hodgesd-nix-config.cachix.org-1:<PUBLIC_KEY_FROM_CACHIX>" ];
};
```

### 4. (Optional) Let the flake-lock PR trigger CI

PRs opened by the default `GITHUB_TOKEN` don't trigger other workflows. To run
Eval/Build automatically on the weekly bump PR, create a PAT with `repo` +
`workflow` scope and save it:

```bash
gh secret set FLAKE_LOCK_PAT
```

### 5. Renovate token

`renovate.yaml` runs Renovate itself (no hosted app to install), so it needs a
token that can open PRs and the Dependency Dashboard issue. Create a
**fine-grained** PAT at <https://github.com/settings/personal-access-tokens/new>
scoped to **this repository only** with Contents *read/write*, Pull requests
*read/write*, Issues *read/write*, then:

```bash
gh secret set RENOVATE_TOKEN
```

Trigger a first run with `gh workflow run renovate.yaml` — it opens the
Dependency Dashboard issue and the first grouped PR if anything is behind.
