# hosts/common/darwin/packages.nix
# Darwin-specific packages (macOS-only applications)
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    aerospace
    iina
    lima
  ];
}
