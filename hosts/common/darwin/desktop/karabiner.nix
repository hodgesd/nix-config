# hosts/common/darwin/karabiner.nix
{ config
, lib
, pkgs
, ...
}: {
  home-manager.users.${config.majordouble.user} = {
    xdg.configFile."karabiner/karabiner.json" = {
      text = ''
              {
                "global": {
          "ask_for_confirmation_before_quitting": true,
          "check_for_updates_on_startup": false,
          "show_in_menu_bar": false,
          "show_profile_name_in_menu_bar": false,
          "unsafe_ui": false
        },
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
      # Force overwrite to prevent .hm-backup files
      force = true;
      # Restart Karabiner to apply changes
      onChange = ''
        /bin/launchctl kickstart -k gui/$(id -u)/org.pqrs.karabiner.karabiner_console_user_server 2>/dev/null || true
      '';
    };
  };
}
