# Agent workbench — herdr + OpenCode + pi for the `agent` user.
#
# An always-on desk for terminal coding agents, reached only over Tailscale
# SSH (`ssh -t agent@nixos-infra-1 herdr`). herdr is a tmux-style
# multiplexer built for agents: a background server keeps panes alive
# across SSH drops, restores the layout after a restart and resumes agent
# panes into their own sessions. OpenCode is the daily driver (permission
# rails seeded on); pi is the minimal, prompt-free harness for cheap or
# scripted runs. Added 2026-09-20.
#
# Shape: three packages from the llm-agents.nix flake input (Tier-2, own
# nixpkgs pin, own binary cache — see flake.nix), two of them behind thin
# wrappers that load the OpenRouter key. Nothing binds on the host and the
# firewall is untouched: herdr's socket is a Unix socket in the agent's
# home, and OpenCode's `serve`/`web` modes are deliberately unused.
#
# Security model — the boundary is the OS user, not the tools:
#   - `agent` is a plain user: no wheel, no docker (root-equivalent), no
#     hermes (would expose /var/lib/hermes/.hermes/.env). pi executes
#     shell commands with no confirmation by design, and OpenCode's rails
#     are a config file the agent user can edit, so a prompt-injected
#     repo must not be able to reach sudo, the docker socket or Hermes.
#   - The OpenRouter key (sops `workbench-env`, owner agent, 0400) is
#     loaded by the wrappers into the agent's process tree only — never
#     the login shell. Its blast radius is the credit limit set on the
#     key at OpenRouter. The agents' bash children inherit it; that is
#     inherent (their own auth.json would be readable the same way).
#   - OpenCode's seeded rails catch accidents (ask on edits and unknown
#     commands; rm/push/sudo denied); the user boundary catches the
#     adversarial case. pi relies on the user boundary alone.
#   - No egress chain for this UID (unlike hermes-egress.nix): a coding
#     workbench legitimately reaches GitHub, npm and tailnet services. If
#     wanted later, hermes-egress.nix's mkChain works with `--uid-owner
#     agent`.
#   - Access is Tailscale SSH (`ssh agent@…`), permitted by the default
#     tailnet SSH policy (autogroup:nonroot). No authorized keys: the LAN
#     DR path is for hodgesd only.
#
# State (all under /home/agent, NOT backed up — repos live in git and
# sessions are disposable; add to backup.nix if that changes):
#   ~/.config/herdr/          config.toml, session.json, herdr.sock
#   ~/.config/opencode/       opencode.json
#   ~/.local/share/opencode/  sessions, auth.json (only if /connect is used)
#   ~/.pi/agent/              settings.json, sessions/, auth.json (only if /login)
#   ~/src                     checkouts
# The three config files are SEEDED ONCE (tmpfiles `C` copies only when
# the target is missing, like the .zshrc `f` rule in nixos-common.nix);
# afterwards they belong to the user and the tools write to them. To
# re-seed one, delete it and run `systemd-tmpfiles --create`.
#
# Persistence: `herdr` starts its server on first launch; ctrl+b q detaches
# and logind's KillUserProcesses=no (NixOS default) keeps it running after
# logout. After a VM reboot the next `herdr` restores the layout and, with
# resume_agents_on_restore, relaunches the agent panes into their sessions.
#
# Update: `nix flake update llm-agents` → `just deploy-check` → `just deploy`
# (the weekly flake-lock PR bumps it too, gated by CI build).
#
# Disable: remove ./agent-workbench.nix from default.nix imports and the
# llm-agents input from flake.nix, deploy. mutableUsers is on, so the
# account survives the switch: `sudo userdel -r agent` on the VM, then drop
# `workbench-env` from secrets/nixos-infra.yaml.
{
  config,
  inputs,
  pkgs,
  system,
  ...
}: let
  llm = inputs.llm-agents.packages.${system};

  # Thin launchers: source the sops dotenv into this process only, then
  # exec the real binary. The `-r` check makes them degrade to a keyless
  # run (e.g. hodgesd trying `pi`) instead of dying on a permission error.
  withKey = name: pkg: extraEnv:
    pkgs.writeShellScriptBin name ''
      if [ -r ${config.sops.secrets.workbench-env.path} ]; then
        set -a
        . ${config.sops.secrets.workbench-env.path}
        set +a
      fi
      ${extraEnv}
      exec ${pkg}/bin/${name} "$@"
    '';
  # Upstream's package already sets these; restating them keeps the
  # no-phone-home intent visible here, not only in a third-party flake.
  pi = withKey "pi" llm.pi ''
    export PI_SKIP_VERSION_CHECK=1 PI_TELEMETRY=0
  '';
  # Nix owns the version: belt (env) and braces (`autoupdate` below).
  opencode = withKey "opencode" llm.opencode ''
    export OPENCODE_DISABLE_AUTOUPDATE=1
  '';

  # Same OpenRouter-namespaced model id hermes.nix uses. Verify in pi's
  # /model picker on first run; Ctrl+S there rewrites the seeded file.
  model = "anthropic/claude-sonnet-5";

  piSettingsText = builtins.toJSON {
    defaultProvider = "openrouter";
    defaultModel = model;
    defaultThinkingLevel = "medium";
  };
  piSettings = pkgs.writeText "pi-settings.json" piSettingsText;

  # Rails on, nothing leaves the box. `share = disabled`: OpenCode's /share
  # publishes a session to opencode.ai. Pushes are denied on purpose — do
  # them yourself in a shell pane; loosen in the user's copy when earned.
  opencodeText = builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";
    model = "openrouter/${model}";
    provider.openrouter.options.apiKey = "{env:OPENROUTER_API_KEY}";
    share = "disabled";
    autoupdate = false;
    permission = {
      edit = "ask";
      webfetch = "ask";
      external_directory = "ask";
      bash = {
        "*" = "ask";
        "git status*" = "allow";
        "git diff*" = "allow";
        "git log*" = "allow";
        "rm *" = "deny";
        "git push*" = "deny";
        "sudo *" = "deny";
      };
    };
    agent.plan.permission = {
      edit = "deny";
      bash = "deny";
    };
  };
  opencodeConfig = pkgs.writeText "opencode.json" opencodeText;

  # Only deliberate settings; everything else is herdr's default.
  herdrText = ''
    # Seeded by nix-config (agent-workbench.nix); yours to edit after that.

    [session]
    # The reboot story: relaunch agent panes into their own sessions when
    # the saved layout is restored.
    resume_agents_on_restore = true

    [ui.toast]
    # Finished / needs-input pings reach the outer terminal over SSH.
    delivery = "terminal"
  '';
  herdrConfig = pkgs.writeText "herdr-config.toml" herdrText;
in {
  users.groups.agent = {};
  users.users.agent = {
    isNormalUser = true;
    group = "agent";
    description = "agent workbench (herdr, opencode, pi)";
    shell = pkgs.zsh;
    # Deliberately no extraGroups — see the security model above.
  };

  # No restartUnits, unlike every other secret on this host: nothing
  # long-running holds the value; each `pi`/`opencode` launch re-reads it.
  sops.secrets.workbench-env = {
    owner = "agent";
    mode = "0400";
  };

  environment.systemPackages = [pi opencode llm.herdr];

  # The tools' own binary cache (see flake.nix). Kept here so removing the
  # module removes the trust; the lists merge with nixos-common.nix's.
  nix.settings = {
    substituters = ["https://cache.numtide.com"];
    trusted-public-keys = ["niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="];
  };

  # Reference copies of the seeds, so what nix would write is visible on
  # the VM (`cat /etc/agent-workbench/opencode.json`) and re-seeding is a
  # plain copy. The tmpfiles sources stay the store files below: /etc
  # entries are symlinks and `C` does not follow them.
  environment.etc = {
    "agent-workbench/pi-settings.json".text = piSettingsText;
    "agent-workbench/opencode.json".text = opencodeText;
    "agent-workbench/herdr-config.toml".text = herdrText;
  };

  # Parents are listed explicitly: tmpfiles would otherwise create them
  # root-owned. `C` copies the store file (root, 0444) only when the
  # target is missing; the `z` line right after hands it to the user.
  systemd.tmpfiles.rules = [
    "d /home/agent/.pi 0750 agent agent -"
    "d /home/agent/.pi/agent 0750 agent agent -"
    "d /home/agent/.config 0750 agent agent -"
    "d /home/agent/.config/herdr 0750 agent agent -"
    "d /home/agent/.config/opencode 0750 agent agent -"
    "d /home/agent/src 0750 agent agent -"
    # No Home Manager for this user either: suppress zsh's first-login
    # wizard (same as nixos-common.nix does for hodgesd).
    "f /home/agent/.zshrc 0644 agent agent -"
    "C /home/agent/.pi/agent/settings.json - - - - ${piSettings}"
    "z /home/agent/.pi/agent/settings.json 0644 agent agent -"
    "C /home/agent/.config/herdr/config.toml - - - - ${herdrConfig}"
    "z /home/agent/.config/herdr/config.toml 0644 agent agent -"
    "C /home/agent/.config/opencode/opencode.json - - - - ${opencodeConfig}"
    "z /home/agent/.config/opencode/opencode.json 0644 agent agent -"
  ];
}
