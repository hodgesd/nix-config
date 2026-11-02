# CI workflows

These workflows verify this config so breakage shows up before `darwin-rebuild switch`.

| Workflow | Trigger | Runner | What it does |
|---|---|---|---|
| `eval.yaml` | every push / PR | Linux (free, fast) | Evaluates every host. Catches syntax errors, bad options, module conflicts, per-host metadata branches. No build. |
| `build.yaml` | `flake.lock` change, nightly, manual | macOS | Full `nix build` of every host (macOS runners for the Macs, Linux for the NixOS VMs); pushes results to Cachix. |
| `renovate.yaml` | weekly, manual | Linux | Self-hosted Renovate: one grouped PR for the homelab compose images and one for `flake.lock` inputs (rules in `/renovate.json`), both gated by Eval/Build. |

## One-time setup

`build.yaml` needs the Cachix cache, `renovate.yaml` needs a PAT, and both
`eval.yaml` and `build.yaml` need the billfiler deploy key (step 5).

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

### 4. Renovate token

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

### 5. billfiler deploy key

`flake.nix` has one private input, `billfiler`. Nix fetches it over `git+ssh`,
which the Macs satisfy with the SSH key they already have — but a runner has
no key, so **every Eval and Build job fails without this**, on all hosts, not
just the Macs.

Use a read-only deploy key scoped to that one repo, not a PAT: a PAT would
give the runner read access to every repo on the account.

Run it wherever `gh` is already authenticated — neither half of the key needs
to persist anywhere, it only has to reach the two endpoints.

```bash
# mktemp -d is 0700 on both macOS and Linux, unlike a guessable /tmp path.
d=$(mktemp -d)

# A throwaway keypair that exists only for CI.
ssh-keygen -t ed25519 -N "" -C "nix-config CI" -f "$d/key"

# Public half -> the billfiler repo, read-only (no --allow-write).
gh repo deploy-key add "$d/key.pub" --repo hodgesd/billfiler --title "nix-config CI"

# Private half -> this repo's secrets.
# --repo, not the cwd's remote: run from the wrong checkout and this would
# store the private key as a secret on THAT repo, where its workflows can read
# it -- while CI here still has nothing.
gh secret set BILLFILER_DEPLOY_KEY --repo hodgesd/nix-config < "$d/key"
rm -rf "$d"
```

Plain `rm`, not `shred`: `shred` is GNU coreutils and macOS does not ship it,
so on a Mac that line would fail and leave the private key on disk — the
opposite of the intent. `rm -P` is no better on APFS by Apple's own
documentation. It is a read-only key scoped to one repo; if in doubt,
`gh repo deploy-key delete` and run this again.

Verify:

```bash
gh repo deploy-key list --repo hodgesd/billfiler
gh secret list --repo hodgesd/nix-config | grep BILLFILER
```

`.github/actions/private-flake-key` installs it before nix runs. It fails with
a named error if the secret is missing, rather than letting nix die on an
opaque credential prompt.

**Renovate does not get this key.** Its `lockFileMaintenance` runs
`nix flake update` inside the Renovate container, which cannot see the
runner's `~/.ssh`, so the weekly `flake.lock` PR will stop being opened. Fix
it by running `just update` by hand, or drop `"nix"` from `enabledManagers` in
`/renovate.json` so Renovate only tracks the compose images and the lockfile
is a manual job.
