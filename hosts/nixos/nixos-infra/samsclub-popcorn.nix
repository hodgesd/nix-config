# TEMPORARY (expires 2026-12-12): alert when Member's Mark Organic Popcorn
# (EVOO + sea salt, 14 oz) can be delivered from the O'Fallon, IL Sam's
# Club. Added 2026-09-13.
#
# Why not changedetection.io: Sam's Club answers both of its fetchers
# (Python requests and the sockpuppetbrowser Chrome) with a "Let us know
# you're not a robot" page, while plain curl from this VM gets the real
# product page. This stays plain curl on purpose: no fingerprint spoofing
# or challenge solving. If curl starts getting the challenge too, the
# "check is broken" alert fires, and the fix is to remove this module,
# not to work around the block.
#
# How: hourly (06–22), fetch the page, read the DELIVERY entry of
# fulfillmentOptions from its __NEXT_DATA__ JSON, and ntfy on each
# OUT_OF_STOCK → in-stock edge (topic `changes`, alongside
# changedetection's alerts). Going out of stock is silent.
#
# The club comes from this VM's IP geolocation, not a cookie. Requests
# Sam's Club flags as bots get a default Dallas club where delivery shows
# IN_STOCK, so a bot flag or any club other than 8285 counts as a failed
# check, never as stock.
#
# Expiry: after `expires` it stops fetching and sends one ntfy a day
# asking to be removed.
#
# Manual test on the VM: `samsclub-popcorn-check --test` (fetch + parse +
# a low-priority ntfy, state untouched). `EXPIRES=2020-01-01
# samsclub-popcorn-check` exercises the expiry reminder against a
# throwaway state dir.
#
# Disable: remove ./samsclub-popcorn.nix from default.nix imports and the
# row in docs/NIXOS-INFRA.md, deploy. State to delete afterwards:
# /var/lib/private/samsclub-popcorn.
{
  lib,
  pkgs,
  ...
}: let
  itemUrl = "https://www.samsclub.com/ip/Member-s-Mark-Organic-Popcorn-with-Extra-Virgin-Olive-Oil-and-Sea-Salt-14-oz/17797355238?classType=REGULAR";
  club = "8285"; # O'Fallon Sam's Club
  expires = "2026-12-12";
  # Tailnet-only ntfy; publishing needs no credentials (same as Gatus and
  # wan-watch), so there is no secret here.
  ntfyUrl = "https://ntfy.jaguar-duckbill.ts.net/changes";
  # The user agent the VM probe got the real page with.
  userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36";

  check = pkgs.writeShellApplication {
    name = "samsclub-popcorn-check";
    runtimeInputs = [pkgs.curl pkgs.htmlq pkgs.jq pkgs.coreutils];
    text = ''
      url=${lib.escapeShellArg itemUrl}
      club=${lib.escapeShellArg club}
      expires=''${EXPIRES:-${expires}}
      ntfy=${lib.escapeShellArg ntfyUrl}

      test_mode=0
      if [ "''${1:-}" = "--test" ]; then
        test_mode=1
      fi

      # Manual runs have no StateDirectory; give them a throwaway one so
      # they can never disturb the timer's state.
      state_dir=''${STATE_DIRECTORY:-}
      if [ -z "$state_dir" ]; then
        state_dir=$(mktemp -d)
        trap 'rm -rf "$state_dir"' EXIT
      fi

      # notify TITLE PRIORITY TAGS MESSAGE [extra curl args...]
      # Titles stay ASCII: ntfy headers don't reliably carry UTF-8.
      notify() {
        local title=$1 priority=$2 tags=$3 message=$4
        shift 4
        curl -fsS -m 10 -H "Title: $title" -H "Priority: $priority" -H "Tags: $tags" \
          "$@" -d "$message" "$ntfy" >/dev/null || echo "ntfy post failed" >&2
      }

      today=$(date +%F)
      if [ "$test_mode" = 0 ] && [[ "$today" > "$expires" ]]; then
        if [ "$(cat "$state_dir/nagged" 2>/dev/null || true)" != "$today" ]; then
          notify "Remove the Sam's Club popcorn check" default wastebasket \
            "This temporary check expired on $expires and has stopped checking. Remove ./samsclub-popcorn.nix from hosts/nixos/nixos-infra/default.nix (and its row in docs/NIXOS-INFRA.md), then just deploy."
          echo "$today" > "$state_dir/nagged"
        fi
        echo "expired on $expires; not checking"
        exit 0
      fi

      # A failed check is never a stock signal. Alert once after 6 in a
      # row (about six daytime hours), then stay quiet until it recovers.
      fail() {
        echo "check failed: $1" >&2
        if [ "$test_mode" = 1 ]; then
          exit 1
        fi
        local count
        count=$(( $(cat "$state_dir/failures" 2>/dev/null || echo 0) + 1 ))
        echo "$count" > "$state_dir/failures"
        if [ "$count" -ge 6 ] && [ ! -e "$state_dir/broken" ]; then
          notify "Sam's Club popcorn check is broken" high warning \
            "$count checks in a row failed: $1. If Sam's Club now blocks curl, remove ./samsclub-popcorn.nix rather than working around it."
          touch "$state_dir/broken"
        fi
        exit 1
      }

      # No -L: the bot wall is a 307 to /are-you-human, which then fails
      # the __NEXT_DATA__ check below with a clear reason.
      if ! html=$(curl -fsS --compressed -m 30 --retry 2 --retry-delay 10 \
          -A ${lib.escapeShellArg userAgent} \
          -H 'Accept: text/html,application/xhtml+xml' \
          -H 'Accept-Language: en-US,en;q=0.9' \
          "$url"); then
        fail "fetch failed"
      fi

      next_data=$(printf '%s' "$html" | htmlq --text 'script#__NEXT_DATA__' || true)
      if [ -z "$next_data" ]; then
        fail "no __NEXT_DATA__ in the page (bot challenge or site redesign)"
      fi

      if ! parsed=$(printf '%s' "$next_data" | jq -er '
          .props.pageProps as $pp
          | $pp.initialData.data.product as $p
          | [ ($pp.isIpLevelBot | tostring),
              ($p.location.storeIds[0] // "none"),
              (first($p.fulfillmentOptions[] | select(.type == "DELIVERY") | .availabilityStatus) // "none")
            ]
          | join(" ")'); then
        fail "unexpected __NEXT_DATA__ shape (site redesign?)"
      fi
      read -r bot got_club status <<< "$parsed"

      if [ "$bot" != false ]; then
        fail "Sam's Club flagged the request as a bot (isIpLevelBot=$bot)"
      fi
      if [ "$got_club" != "$club" ]; then
        fail "page is for club $got_club, not $club (did the VM's IP geolocation move?)"
      fi
      if [ "$status" = none ]; then
        fail "no DELIVERY option on the page"
      fi

      line="DELIVERY $status club=$got_club bot=$bot"
      echo "$line"

      if [ "$test_mode" = 1 ]; then
        notify "Test: Sam's Club popcorn check" low test_tube \
          "Fetch, parse and ntfy all work. Currently: $line"
        exit 0
      fi

      rm -f "$state_dir/failures" "$state_dir/broken"

      # Edge-triggered: alert on OUT_OF_STOCK -> anything else. Any other
      # status alerts too; a rare false alarm beats a missed restock.
      prev=$(cat "$state_dir/state" 2>/dev/null || echo OUT_OF_STOCK)
      if [ "$prev" = OUT_OF_STOCK ] && [ "$status" != OUT_OF_STOCK ]; then
        notify "Popcorn: delivery in stock at O'Fallon Sam's Club" high popcorn \
          "Member's Mark Organic Popcorn (EVOO + sea salt, 14 oz): delivery is $status. Temporary check, expires $expires - remove samsclub-popcorn.nix when done." \
          -H "Click: $url"
      fi
      echo "$status" > "$state_dir/state"
    '';
  };
in {
  # On PATH for the manual --test run; goes away with the module.
  environment.systemPackages = [check];

  systemd.services.samsclub-popcorn = {
    description = "Sam's Club popcorn delivery-stock check (temporary, expires ${expires})";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      DynamicUser = true;
      StateDirectory = "samsclub-popcorn";
      PrivateTmp = true;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ExecStart = lib.getExe check;
    };
  };

  systemd.timers.samsclub-popcorn = {
    wantedBy = ["timers.target"];
    timerConfig = {
      # Hourly 06:00–22:00 Central (time.timeZone in nixos-common.nix);
      # overnight restocks show up at the 06:00 check.
      OnCalendar = "*-*-* 06..22:00:00";
      RandomizedDelaySec = "10m";
    };
  };
}
