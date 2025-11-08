# hosts/common/darwin/defaults/security.nix
# Security, privacy, and system update preferences
{ ... }:
{
  system.defaults.CustomUserPreferences = {
    "com.apple.AdLib".allowApplePersonalizedAdvertising = false;
    "com.apple.SoftwareUpdate" = {
      AutomaticCheckEnabled = true;
      ScheduleFrequency = 1;
      AutomaticDownload = 1;
      CriticalUpdateInstall = 1;
    };
    "com.apple.TimeMachine".DoNotOfferNewDisksForBackup = true;
    "com.apple.ImageCapture".disableHotPlug = true;
    "com.apple.commerce".AutoUpdate = true;
  };
}
