# Host-specific configuration for mbp (M3 Pro Laptop)
# Laptop power/menu-bar defaults are shared via hosts/common/darwin/laptop-defaults.nix
# Tailscale (cask + CLI wrapper) is shared via hosts/common/darwin/tailscale.nix
_: {
  # Enable wallpaper management
  majordouble.wallpaper = {
    enable = true;
    path = "/Users/hodgesd/Documents/Wallpapers/Gulfstream GV at Waimea.jpg";
  };
}
