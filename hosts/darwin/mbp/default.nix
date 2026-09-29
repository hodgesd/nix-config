# Host-specific configuration for mbp (M3 Pro Laptop)
# Laptop power/menu-bar defaults are shared via hosts/common/darwin/laptop-defaults.nix
# Tailscale (cask + CLI wrapper) is shared via hosts/common/darwin/tailscale.nix
_: {
  # Wallpaper: the default `path` is ~/Documents/Wallpapers (a folder). Nix
  # selects the folder via desktoppr; the "Change picture" toggle and interval
  # are a one-time System Settings step (see modules/wallpaper.nix). Set
  # `path` to a single image for a static wallpaper instead.
  majordouble.wallpaper.enable = true;
}
