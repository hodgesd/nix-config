# hosts/common/darwin/defaults/general.nix
# General macOS system preferences (NSGlobalDomain)
{...}: {
  system.defaults = {
    NSGlobalDomain.AppleShowAllExtensions = true;
    NSGlobalDomain.AppleShowScrollBars = "Always";
    NSGlobalDomain.NSUseAnimatedFocusRing = false;
    NSGlobalDomain.NSNavPanelExpandedStateForSaveMode = true;
    NSGlobalDomain.NSNavPanelExpandedStateForSaveMode2 = true;
    NSGlobalDomain.PMPrintingExpandedStateForPrint = true;
    NSGlobalDomain.PMPrintingExpandedStateForPrint2 = true;
    NSGlobalDomain.ApplePressAndHoldEnabled = false;
    NSGlobalDomain.NSWindowShouldDragOnGesture = true;
    NSGlobalDomain.NSAutomaticSpellingCorrectionEnabled = false;
    LaunchServices.LSQuarantine = false;
    loginwindow.GuestEnabled = false;
    # Solid menus and Dock: the glass let windows behind SwiftBar menus show
    # through as light and dark patches.
    universalaccess.reduceTransparency = true;
  };
}
