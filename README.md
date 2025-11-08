# 🛠️ My Nix Config

## 💻 Machines

| Hostname | Model                  | Storage (Ram/HD) | Cores (CPU/GPU) |
|----------|------------------------|------------------|-----------------|
| `mini`   | Mac Mini M2 Pro        | —                |                 |
| `mbp`    | MacBook Pro M3 Pro 14" | 18GB / 1TB       | 12 / 18         |
| `air`    | MacBook Air M1 13"     | 16GB / 500GB     | 8 / 7           |
| `nixair`  | MacBook Air i7-5650U   | 8GB / 500GB      | 2 / 1           |

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

### 7. Manually Installed Apps
- [llm](https://llm.datasette.io/en/stable/)
  - `uv tool install llm`  
  - `llm install llm-mlx` # MLX plugin  
  - `llm mlx download-model mlx-community/Mistral-7B-Instruct-v0.3-4bit`    # mlx model
  - `llm aliases set m7b mlx-community/Mistral-7B-Instruct-v0.3-4bit`
  - `llm models default m7b`
