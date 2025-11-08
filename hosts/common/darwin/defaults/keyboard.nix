# hosts/common/darwin/defaults/keyboard.nix
# Keyboard and input preferences
{ ... }:
{
  system.defaults = {
    NSGlobalDomain.InitialKeyRepeat = 25;
    NSGlobalDomain.KeyRepeat = 2;
    NSGlobalDomain."com.apple.mouse.tapBehavior" = 1;
  };
}
