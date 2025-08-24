# hosts/common/karabiner.nix
{ config, lib, pkgs, ... }:

{
  home-manager.users.hodgesd = {
    xdg.configFile."karabiner/karabiner.json" = {
      text = ''
        {
          "global": { "check_for_updates_on_startup": true },
          "profiles": [
            {
              "name": "Default",
              "selected": true,
              "complex_modifications": {
                "rules": [
                  {
                    "description": "Caps Lock: tap = toggle, hold = hyper",
                    "manipulators": [
                      {
                        "from": { "key_code": "caps_lock" },
                        "to": [{ 
                          "key_code": "left_shift",
                          "modifiers": ["left_control", "left_option", "left_command"] 
                        }],
                        "to_if_alone": [{ 
                          "key_code": "caps_lock",
                          "hold_down_milliseconds": 200
                        }],
                        "type": "basic"
                      }
                    ]
                  }
                ]
              }
            }
          ]
        }
      '';
      force = true;
    };
  };
}
