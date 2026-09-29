# lib/options.nix
# Custom options shared by darwin and NixOS hosts. Feature options live with
# their module (e.g. majordouble.wallpaper in modules/wallpaper.nix).
{lib, ...}: {
  options.majordouble.user = lib.mkOption {
    type = lib.types.str;
    default = "hodgesd";
    description = "Primary user name";
  };
}
