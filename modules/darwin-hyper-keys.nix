# modules/hyper-hotkeys.nix
{ config, pkgs, lib, ... }:

{
  services.skhd.enable = true;

  homebrew.casks = lib.mkAfter [ "karabiner-elements" ];
  };

  xdg.configFile."skhd/skhdrc".text = ''
    hyper - s : open -a "Safari"
    hyper - d : open -a "Drafts"
    hyper - c : open -a "ChatGPT"
	hyper - w : open -a "Warp"
    hyper - p : open -a "PyCharm"
    hyper - f : open -a "Finder"
  '';

  xdg.configFile."karabiner/karabiner.json".text = ''
  {
    "global": { "check_for_updates_on_startup": true },
    "profiles": [
      {
        "name": "Default",
        "selected": true,
        "complex_modifications": {
          "rules": [
            {
              "description": "Caps Lock: tap = CapsLock, hold = Hyper (⌃⌥⌘⇧)",
              "manipulators": [
                {
                  "type": "basic",
                  "from": { "key_code": "caps_lock", "modifiers": { "optional": ["any"] } },
                  "to": [
                    { "key_code": "left_shift", "modifiers": ["left_control", "left_option", "left_command"] }
                  ],
                  "to_if_alone": [
                    { "key_code": "caps_lock" }
                  ]
                }
              ]
            }
          ]
        }
      }
    ]
  }
  '';
}
