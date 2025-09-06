# 🛠️ My Nix Config

## 💻 Machines

| Hostname  | Model                  | Storage (RAM/SSD) | OS   |
|-----------|------------------------|-------------------|:----:|
| `mini`    | Mac Mini M2 Pro        | 16GB / 512GB      |     |
| `mbp`     | MacBook Pro M3 Pro 14" | 18GB / 1TB        |     |
| `air`     | MacBook Air M1 13"     | 8GB / 256GB       |     |
| `air-nix` | MacBook Air i7 13"     | 8GB / 512GB       | ❄️   |

## 🍎 Mac Fresh Install Checklist

### 1. Set machine name (mini / mbp / air)
```chmod +x set_mac_name.sh && ./set_mac_name.sh```

### 2. Install Nix (Determinate Systems)
```sh <(curl -L https://install.determinate.systems/nix)```

### 3. Clone repo + enter
```git clone https://github.com/hodgesd/nix-config.git && cd nix-config```

### 4. Bootstrap essentials and apply config
```
brew install just
just macos:bootstrap
just
```

### 5. Manually Installed Apps
- [ ] [llm](https://llm.datasette.io/en/stable/)  
  ```bash
  uv tool install llm
  llm install llm-mlx   # MLX plugin
  llm mlx download-model mlx-community/Mistral-7B-Instruct-v0.3-4bit  # mlx model
  llm aliases set m7b mlx-community/Mistral-7B-Instruct-v0.3-4bit
  llm models default m7b
