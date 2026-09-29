# modules/wallpaper.nix
# Home Manager module: select the macOS wallpaper (file or folder) with
# desktoppr at activation. https://github.com/scriptingosx/desktoppr
#
# Folder semantics on macOS 14+ (verified on 27.0, 2026-09-28): desktoppr
# records the folder as the wallpaper "choice" but does NOT turn on
# "Change picture" — the schedule ("Shuffle") stays empty in
# ~/Library/Application Support/com.apple.wallpaper/Store/Index.plist, so the
# README's "the system will rotate" only holds for pre-Sonoma macOS. Nothing
# scriptable flips it: desktoppr has no flag, and System Events'
# `picture rotation` write fails with -10000. So rotation is: Nix selects the
# folder here, then a one-time toggle in System Settings → Wallpaper
# ("Change picture" + interval; "Show on all Spaces" if offered). See README.
#
# Why not a launchd loop calling `desktoppr <random file>`: that NSWorkspace
# call only changes the current Space per screen; the native engine is
# Spaces-aware and survives reboots.
#
# Once-per-path guard: re-running desktoppr on the folder rewrites the choice
# with an empty schedule, i.e. it would silently switch rotation off on every
# rebuild. A marker file records the last applied path so activation only
# touches the wallpaper when `path` changes (or the marker is deleted).
# desktoppr's own read-back is no use as a guard: with rotation off it prints
# the folder's parent, with rotation on the folder (desktoppr issue 20).
#
# desktoppr comes from the Homebrew cask (hosts/common/darwin/homebrew.nix);
# its pkg installs to /usr/local/bin. nixpkgs has it too, but it drags ~190 MB
# of Swift runtime into every closure — not worth it for a 270 KB tool.
{
  config,
  lib,
  wallpaper ? null,
  ...
}:
lib.mkIf (wallpaper != null && wallpaper.enable) {
  home.activation.setWallpaper = lib.hm.dag.entryAfter ["writeBoundary"] ''
    WP_PATH="${wallpaper.path}"
    DESKTOPPR=/usr/local/bin/desktoppr
    MARKER="${config.xdg.stateHome}/nix-wallpaper/applied"

    if [ -f "$MARKER" ] && [ "$(cat "$MARKER")" = "$WP_PATH" ]; then
      echo "Wallpaper already applied ($WP_PATH); delete $MARKER to re-apply."
    elif [ ! -e "$WP_PATH" ]; then
      echo "Warning: wallpaper path not found: $WP_PATH — skipping."
    elif [ ! -x "$DESKTOPPR" ]; then
      echo "Warning: desktoppr not found at $DESKTOPPR — skipping."
      echo "It is declared as a Homebrew cask; a full 'just' switch installs it."
    else
      echo "Setting wallpaper to $WP_PATH..."
      if $DRY_RUN_CMD "$DESKTOPPR" "$WP_PATH"; then
        $DRY_RUN_CMD mkdir -p "$(dirname "$MARKER")"
        if [ -z "$DRY_RUN_CMD" ]; then
          printf '%s\n' "$WP_PATH" > "$MARKER"
        fi
        if [ -d "$WP_PATH" ]; then
          echo "Folder selected. Rotation is a one-time toggle: System Settings → Wallpaper → Change picture."
        fi
      fi
    fi
  '';
}
