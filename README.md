# 🛠️ My Nix Config

A modular, well-documented Nix configuration managing both macOS (via nix-darwin) and NixOS systems.

## ✨ Features

- 🔧 Modular configuration structure
- 🤖 Machine metadata system for conditional configs
- 📦 Declarative package management (Nix + Homebrew)
- 🏠 Home Manager integration
- 📚 Comprehensive documentation
- 🔄 Easy rollbacks and reproducibility

## 📖 Documentation

- **[STRUCTURE.md](docs/STRUCTURE.md)** - Configuration layout and organization
- **[ADDING_MACHINE.md](docs/ADDING_MACHINE.md)** - Step-by-step guide to add new machines
- **[HOMEBREW.md](docs/HOMEBREW.md)** - Managing Homebrew packages and Mac App Store apps
- **[CUSTOMIZATION.md](docs/CUSTOMIZATION.md)** - Common customization tasks

## 💻 Machines

| Hostname    | OS | Model                  | Storage (Ram/HD) | Cores (CPU/GPU) |
|-------------|--|------------------------|------------------|-----------------|
| `mini`      | 🍏 | Mac Mini M2 Pro        | —                |                 |
| `mbp`       | 🍏 | MacBook Pro M3 Pro 14" | 18GB / 1TB       | 12 / 18         |
| `air`       | 🍏 | MacBook Air M1 13"     | 16GB / 500GB     | 8 / 7           |
| `nixos-air` | ❄️ | MacBook Air i7-5650U   | 8GB / 500GB      | 2 / 1           |

## 🍎 Mac Installation

> **Note:** For **existing systems** with apps/data, see the [Safe Migration Guide](pre_install_audit.sh) to preserve your apps.

### Fresh Install Checklist

Use this for brand new Mac installations with no existing setup.

**1. Create User**

- [ ] Create user `hodgesd`

**2. Update macOS**

- [ ] Open **System Settings** → **Software Update** → **Upgrade Now**

**3. Install Xcode Command Line Tools**

```bash
xcode-select --install
```

**4. Clone Nix-Config Repo**

```bash
cd ~
git clone https://github.com/hodgesd/nix-config.git
cd nix-config
```

**5. Set Machine Hostname**

Set to one of the [machine names above](#machines):

```bash
chmod +x set_mac_name.sh
./set_mac_name.sh
# Or manually:
# sudo scutil --set HostName <hostname>
# sudo scutil --set LocalHostName <hostname>
# sudo scutil --set ComputerName <hostname>
```

**6. Install Nix**

Using the [Determinate Nix Installer](https://determinate.systems/posts/determinate-nix-installer/):

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

Restart your terminal or source the environment:

```bash
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
```

**7. Bootstrap nix-darwin**

First-time installation command:

```bash
cd ~/nix-config
nix run nix-darwin -- switch --flake .#<hostname>
```

Replace `<hostname>` with your machine name (e.g., `mini`, `mbp`, `air`).

This will take 15-30 minutes to download and install everything.

**8. Restart Shell**

```bash
exec zsh
```

**9. Future Updates**

After the initial bootstrap, use:

```bash
darwin-rebuild switch --flake .#<hostname>
```

### Existing System Migration

If you have an existing Mac with apps and data, use the migration workflow:

**1. Run Pre-Install Audit**

```bash
cd ~/nix-config
./pre_install_audit.sh
```

**2. Review and Preserve Apps**

- Compare audit output with `hosts/common/darwin/homebrew.nix`
- Add important apps to the config before installing
- See migration plan for detailed steps

**3. Temporarily Disable Cleanup**

In `hosts/common/darwin/homebrew.nix`, set:

```nix
onActivation = {
  cleanup = "none";  # Prevents app removal during first install
```

**4. Follow Fresh Install Steps 3-9**

After nix-darwin is installed, use `find_unmanaged_apps.sh` to identify remaining unmanaged apps.

### Post-Install Configuration

**Wallpaper Rotation (mini)**

Set up wallpaper rotation manually via System Settings:

1. Ensure folder exists (iCloud synced):
   ```bash
   mkdir -p ~/Documents/Wallpapers
   ```

2. Configure in System Settings:
   - Open **System Settings** > **Wallpaper**
   - Add folder: `/Users/hodgesd/Documents/Wallpapers/`
   - Enable **"Change picture"** with desired interval

**Manually Installed Apps**

Some apps are not available via Nix/Homebrew and must be installed manually:

- [llm](https://llm.datasette.io/en/stable/) - CLI for LLMs with MLX support
  ```bash
  uv tool install llm --with sentencepiece
  llm install llm-mlx llm-hacker-news
  llm mlx download-model mlx-community/Mistral-7B-Instruct-v0.3-4bit
  llm aliases set m7b mlx-community/Mistral-7B-Instruct-v0.3-4bit
  llm models default m7b
  ```

## 🚀 Quick Commands

```bash
# Build and activate configuration (current host)
darwin-rebuild switch --flake .

# Build specific host
darwin-rebuild switch --flake .#mbp

# Update flake inputs (get latest packages)
nix flake update

# Check configuration for errors
nix flake check

# Rollback to previous generation
darwin-rebuild switch --rollback

# See what changed in last build
darwin-rebuild --list-generations

# Audit unmanaged apps (after nix-darwin installed)
./find_unmanaged_apps.sh
```

## 📁 Configuration Structure

```
nix-config/
├── flake.nix              # Main flake configuration
├── lib/                   # Helper functions and machine metadata
│   ├── machines.nix       # Machine metadata registry
│   └── helpers.nix        # mkDarwin/mkNixos functions
├── hosts/
│   ├── common/            # Shared configurations
│   │   ├── darwin/        # Darwin-specific modules (modular!)
│   │   └── nixos/         # NixOS-specific modules
│   ├── darwin/            # Per-machine Darwin configs
│   └── nixos/             # Per-machine NixOS configs
├── home/                  # Home Manager configurations
├── modules/               # Custom modules
└── docs/                  # Documentation
```

See [STRUCTURE.md](docs/STRUCTURE.md) for detailed information.

## 🔧 Common Tasks

- **Add a package**: Edit `hosts/common/common-packages.nix`
- **Add Homebrew app**: Edit `hosts/common/darwin/homebrew.nix`
- **Change dock**: Edit `hosts/common/darwin/defaults/dock.nix` or host config
- **Modify system settings**: Edit files in `hosts/common/darwin/defaults/`
- **Add keyboard shortcut**: Edit `hosts/common/darwin/desktop/skhd.nix`
- **Add a new machine**: See [ADDING_MACHINE.md](docs/ADDING_MACHINE.md)
- **Audit installed apps**: Run `./find_unmanaged_apps.sh` (after nix-darwin installed)
- **Pre-install audit**: Run `./pre_install_audit.sh` (before nix-darwin installed)

For more, see [CUSTOMIZATION.md](docs/CUSTOMIZATION.md).

## 🛡️ Safety Features

- **Rollback capability**: Every change creates a new generation you can rollback to
- **Declarative**: Configuration is version-controlled and reproducible
- **Non-destructive**: System settings can be changed back anytime
- **App protection**: Set `cleanup = "none"` in homebrew.nix to prevent app removal

## 📝 Helper Scripts

- `pre_install_audit.sh` - Audit system before installing nix-darwin
- `find_unmanaged_apps.sh` - Find apps not managed by nix after installation
- `set_mac_name.sh` - Easily set hostname to match configuration
- `find_unmanaged_apps.sh` - Identify apps not in your nix config
