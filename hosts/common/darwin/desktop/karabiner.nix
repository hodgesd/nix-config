# hosts/common/darwin/karabiner.nix
{
  config,
  lib,
  pkgs,
  ...
}: {
  home-manager.users.${config.majordouble.user} = {
    xdg.configFile."karabiner/karabiner.json" = {
      text = ''
        {
          "global": { "check_for_updates_on_startup": true },
          "profiles": [
            {
              "name": "Default",
              "selected": true,
              "virtual_hid_keyboard": {
              "keyboard_type": "ansi"
              },
              "complex_modifications": {
                "rules": [
                  {
                    "description": "Caps Lock: tap = toggle, hold = meh",
                    "manipulators": [
                      {
                        "from": { "key_code": "caps_lock" },
                        "to": [{
                          "key_code": "left_shift",
                          "modifiers": ["left_control", "left_option"]
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
