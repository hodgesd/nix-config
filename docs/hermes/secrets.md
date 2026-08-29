# Hermes secrets — how credentials flow (Phase 0)

The repo's secrets mechanism is **sops-nix** (already wired before Phase 0;
nothing new was built — this documents the pattern every later phase reuses).

## The pattern

- Ciphertext lives in git: `secrets/nixos-infra.yaml` (VM) and
  `secrets/mini.yaml` (Mac mini). This repo is public — nothing sensitive is
  ever committed in plaintext, including "harmless" values like Telegram user
  IDs (the allowlist is ciphertext deliberately).
- Recipients are declared in `.sops.yaml`:
  - `admin_hodgesd` — the Mac editing key (`~/.config/sops/age/keys.txt`).
    The private key is backed up in the password manager; losing it means you
    can no longer *edit* secrets (hosts can still decrypt their own).
  - `host_nixos_infra` / `host_mini` — derived from each host's SSH host key
    via `ssh-to-age`. Reinstalling a host regenerates its key: re-run
    `ssh-keyscan -t ed25519 <host> | ssh-to-age`, update `.sops.yaml`, then
    `sops updatekeys secrets/<host>.yaml`.
- On the VM, secrets decrypt to `/run/secrets/<name>` during activation.
  **A decryption failure aborts activation before services restart** — a bad
  deploy can't take a working service down with a missing secret.

## Edit / deploy loop

```bash
sops secrets/nixos-infra.yaml   # decrypts in $EDITOR, re-encrypts on save
just deploy-check               # eval + dry-run
just deploy                     # build on Mac, activate on VM
```

## The Hermes-specific quirks (learned the hard way)

1. **`hermes-env` is a dotenv blob, not per-key secrets.** One sops entry
   holds `ANTHROPIC_API_KEY`, `TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USERS`,
   `OPENROUTER_API_KEY` in dotenv format. Add keys by editing the blob.
2. **`environmentFiles` is not systemd's `EnvironmentFile`.** The upstream
   hermes-agent module merges the listed files into
   `/var/lib/hermes/.hermes/.env` (0640 `hermes:hermes`) at activation;
   hermes loads that itself via dotenv. Consequence:
   `docker exec hermes-agent printenv` will NOT show the keys — check
   `/data/.hermes/.env` inside the container instead.
3. **`restartUnits` is mandatory.** systemd restarts a service when its unit
   changes, not when a secret's *contents* change.
   `sops.secrets.hermes-env.restartUnits = ["hermes-agent.service"]` is what
   makes an allowlist edit actually reach the running agent on deploy.
4. **Flakes only see tracked files.** A new secrets file (or any new file)
   must be `git add`ed before `nix eval`/`build`/`just deploy-check` can see
   it. Symptom otherwise: "path does not exist" on a file that's clearly there.

## Adding a credential for a future phase (the recipe)

1. `sops secrets/nixos-infra.yaml` → add `phase-thing-token: <value>` (or a
   new dotenv blob if the consumer wants a file).
2. In the host config: `sops.secrets.phase-thing-token = { restartUnits = [ "the-service.service" ]; };`
3. Reference it **by path only**: `config.sops.secrets.phase-thing-token.path`
   (never the value — evaluation would leak it into the world-readable store).
4. `just deploy-check && just deploy`.

One credential per integration, minimum scope, individually revocable
service-side — see `hermes-integration-plan.md` §3 for the standing rules.
