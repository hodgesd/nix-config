# 🛠️ My Nix Config

A modular, well-documented Nix configuration managing macOS systems via nix-darwin.

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

| Hostname    | OS | Model                  | User           | Storage (Ram/HD) | Cores (CPU/GPU) |
|-------------|--|------------------------|----------------|------------------|-----------------|
| `mini`      | 🍏 | Mac Mini M2 Pro        | `derrickhodges`| —                |                 |
| `mbp`       | 🍏 | MacBook Pro M3 Pro 14" | `hodgesd`      | 18GB / 1TB       | 12 / 18         |
| `air`       | 🍏 | MacBook Air M1 13"     | `hodgesd`      | 16GB / 500GB     | 8 / 7           |

## 🍎 Mac Installation

Choose your installation path:
- **[Fresh Install](#fresh-install)** - Brand new Mac, no existing apps
- **[Existing System](#existing-system)** - Mac with apps/data to preserve

---

### Fresh Install

**Prerequisites**
- [ ] Create user (see [Machines](#machines) table for username per host)
- [ ] Update macOS: **System Settings** → **Software Update** → **Upgrade Now**

**Step 1: Install Xcode Command Line Tools**

Check if already installed:
```bash
xcode-select -p
# If installed, shows: /Library/Developer/CommandLineTools
# If not installed, shows: error message
```

Install if needed:
```bash
xcode-select --install
```

**Step 2: Clone Repository**

```bash
cd ~
git clone https://github.com/hodgesd/nix-config.git
cd nix-config
```

**→ Go to [Common Installation Steps](#common-installation-steps)**

---

### Existing System

**Prerequisites**
- [ ] Time Machine backup recommended
- [ ] Block out 1-2 hours for installation

**Step 1: Install Xcode Command Line Tools**

Check if already installed:
```bash
xcode-select -p
# If installed, shows: /Library/Developer/CommandLineTools (or /Applications/Xcode.app/...)
# If not installed, shows: error message
```

Install if needed:
```bash
xcode-select --install
```

**Step 2: Clone Repository**

```bash
cd ~
git clone https://github.com/hodgesd/nix-config.git
cd nix-config
```

**Step 3: Run Pre-Install Audit**

Identify apps to preserve:

```bash
./pre_install_audit.sh
```

This will:
- List all Homebrew casks/formulas (⚠️ at risk of removal)
- Show all applications
- Identify non-Homebrew apps (✓ safe from removal)
- Optionally generate manual app checklist

**Step 4: Update Configuration**

Edit `hosts/common/darwin/homebrew.nix`:

1. **Add apps to preserve:**
   ```nix
   casks = [
     # ... existing casks ...
     "your-important-app"  # Add from audit
   ];
   ```

2. **Disable cleanup temporarily:**
   ```nix
   onActivation = {
     cleanup = "none";  # ← Change from "zap" to "none"
     autoUpdate = true;
     upgrade = true;
   };
   ```

**→ Go to [Common Installation Steps](#common-installation-steps)**

---

### Common Installation Steps

**Step A: Set Hostname**

Set to one of the [machine names](#machines) (e.g., `mini`, `mbp`, `air`):

```bash
chmod +x set_mac_name.sh
./set_mac_name.sh

# Or manually:
sudo scutil --set HostName <hostname>
sudo scutil --set LocalHostName <hostname>
sudo scutil --set ComputerName <hostname>

# Verify:
hostname -s
```

**Step B: Install Nix**

Using the [official Nix installer](https://nixos.org/download.html):

```bash
sh <(curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install)
```

The installer automatically uses multi-user mode on macOS, which provides:
- ✅ Flakes enabled automatically on macOS
- ✅ Nix daemon for better performance
- ✅ Proper permissions setup

After installation completes, restart your terminal or source:

```bash
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
```

**Step C: Bootstrap nix-darwin**

First-time installation:

```bash
cd ~/nix-config
sudo nix --extra-experimental-features "nix-command flakes" run nix-darwin -- switch --flake .#<hostname>

# Examples:
# nix --extra-experimental-features "nix-command flakes" run nix-darwin -- switch --flake .#mini
# nix --extra-experimental-features "nix-command flakes" run nix-darwin -- switch --flake .#mbp
```

⚠️ **Note:** Experimental features flags are required for first-time bootstrap. After installation, these are enabled automatically.

⏱️ **Expected time:** 15-30 minutes

**Step D: Restart Shell**

```bash
exec zsh
```

**Step E: Future Updates**

After initial bootstrap, use:

```bash
darwin-rebuild switch --flake .
```

---

### Post-Install (Existing Systems Only)

After verifying everything works:

1. **Find remaining unmanaged apps:**
   ```bash
   ./find_unmanaged_apps.sh
   ```

2. **Optional: Re-enable cleanup** in `homebrew.nix`:
   ```nix
   onActivation.cleanup = "zap";  # or "uninstall" or keep "none"
   ```

3. **Rebuild:**
   ```bash
   darwin-rebuild switch --flake .
   ```

### Post-Install Configuration

**Wallpaper Rotation (mini)**

Set up wallpaper rotation manually via System Settings:

1. Ensure folder exists (iCloud synced):
   ```bash
   mkdir -p ~/Documents/Wallpapers
   ```

2. Configure in System Settings:
   - Open **System Settings** > **Wallpaper**
   - Add folder: `~/Documents/Wallpapers/`
   - Enable **"Change picture"** with desired interval

**Hotkeys (skhd + Karabiner Elements)**

1. Launch Karabiner Elements: `open -a Karabiner-Elements`
2. Grant Accessibility permissions: **System Settings** → **Privacy & Security** → **Accessibility** → Enable `skhd` and `Karabiner-Elements`
3. Start skhd service: `brew services start skhd-zig`
4. Test: Press `shift + ctrl + alt + y` (creates `~/skhd-test.log`)

**Note:** Enable "Launch at login" in Karabiner Elements preferences.

**Manual App Setup**
- Reminders Menubar: enable “Launch at login”; bind `meh-r`.
- iStat Menus: add registration key.
- Launch at login: Raycast, Rectangle, SwiftBar, Ice.

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
│   └── helpers.nix        # mkDarwin function
├── hosts/
│   ├── common/            # Shared configurations
│   │   └── darwin/        # Darwin-specific modules (modular!)
│   └── darwin/            # Per-machine Darwin configs
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

- **`pre_install_audit.sh`** - Audit system BEFORE installing nix-darwin
  - Lists all Homebrew casks/formulas
  - Identifies non-Homebrew apps
  - Generates manual app checklist
- **`find_unmanaged_apps.sh`** - Find apps not managed by nix AFTER installation
  - Compares installed apps with nix config
  - Identifies apps to add to homebrew.nix
- **`set_mac_name.sh`** - Set hostname to match configuration
