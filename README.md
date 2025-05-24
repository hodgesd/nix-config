# 🛠️ My Nix Config

## 💻 Machines

| Name   | Description           | Specs       |
|--------|-----------------------|-------------|
| `mini` | M2 Pro Mac Mini       | —           |
| `mbp`  | M3 Pro MacBook Pro    | 18GB / 1TB  |
| `air`  | M1 MacBook Air        | —           |

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
