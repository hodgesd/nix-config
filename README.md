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

## 🍎 Mac Fresh Install Checklist

### 1. Create User

- [ ] Create user `hodgesd`

### 2. Update macOS

- [ ] Open **System Settings**  
  → **Software Update**  
  → **Download Updates**  
  → **Upgrade Now**

### 3. Install [Xcode Command Line Tools](https://developer.apple.com/xcode/resources/)

```bash
xcode-select --install
```

### 4. Set machine name... to one of the [names above](#machines)

```shell
chmod +x set_mac_name.sh
./set_mac_name.sh
```

### 5. Clone Nix-Config Repo

```shell
git clone https://github.com/hodgesd/nix-config.git
```

### 6. Run [Determinate Nix Installer](https://determinate.systems/posts/determinate-nix-installer/)

### 7. Build Configuration

```shell
cd nix-config
darwin-rebuild switch --flake .#<hostname>
```

### 8. Manually Installed Apps
- [llm](https://llm.datasette.io/en/stable/)
  - `uv tool install llm`
  - `llm install llm-mlx` # MLX plugin
  - `llm mlx download-model mlx-community/Mistral-7B-Instruct-v0.3-4bit`    # mlx model
  - `llm aliases set m7b mlx-community/Mistral-7B-Instruct-v0.3-4bit`
  - `llm models default m7b`

## 🚀 Quick Commands

```bash
# Build and activate configuration
darwin-rebuild switch --flake .

# Build specific host
darwin-rebuild switch --flake .#mbp

# Update flake inputs
nix flake update

# Check configuration
nix flake check

# Rollback to previous generation
darwin-rebuild switch --rollback
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
- **Change dock**: Edit `hosts/common/darwin/dock-presets.nix` or host config
- **Modify system settings**: Edit files in `hosts/common/darwin/defaults/`
- **Add keyboard shortcut**: Edit `hosts/common/darwin/skhd.nix`
- **Add a new machine**: See [ADDING_MACHINE.md](docs/ADDING_MACHINE.md)

For more, see [CUSTOMIZATION.md](docs/CUSTOMIZATION.md).
