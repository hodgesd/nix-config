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
                    "keyboard_type_v2": "ansi"
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
      # Karabiner hot-reloads karabiner.json on its own; the restart is a
      # belt-and-braces reconnect to the grabber (Karabiner-Core-Service
      # since 15.7), which can drop the console user server across
      # sleep/wake and stop remapping until one reconnects.
      #
      # The launchd label depends on the installed Karabiner: 16.x folded
      # karabiner_console_user_server, Menu and NotificationWindow into one
      # Karabiner-Console-User-Server agent, while a host still on the
      # cask's 15.6.0 only has the old label. Try the new one first and
      # fall back; never fail the activation over this. Check with
      # `launchctl print gui/$(id -u) | grep pqrs`.
      #
      # Upgrading 15.x -> 16.x disables the services entirely until
      # Karabiner-Elements.app is opened once and "Karabiner-Elements
      # Privileged Daemons v2" is allowed under Login Items & Extensions;
      # no kickstart can substitute for that (mbp, 2026-09-25, via the
      # in-app updater rather than brew).
      onChange = ''
        for label in org.pqrs.service.agent.Karabiner-Console-User-Server \
                     org.pqrs.service.agent.karabiner_console_user_server; do
          /bin/launchctl kickstart -k gui/$(id -u)/$label 2>/dev/null && break
        done
        true
      '';
    };
  };
}
