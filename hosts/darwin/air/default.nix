{ ... }:
let
  dockPresets = import ../../common/darwin/dock-presets.nix;
in
{
  system.defaults.dock.persistent-apps = dockPresets.developer;
}