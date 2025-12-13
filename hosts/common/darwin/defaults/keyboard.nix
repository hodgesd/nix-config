# hosts/common/darwin/defaults/keyboard.nix
# Keyboard and input preferences
{...}: {
  # Required for skhd and Karabiner to intercept keyboard events
  system.keyboard.enableKeyMapping = true;

  system.defaults = {
    NSGlobalDomain.InitialKeyRepeat = 25;
    NSGlobalDomain.KeyRepeat = 2;
    NSGlobalDomain."com.apple.mouse.tapBehavior" = 1;
  };
}
