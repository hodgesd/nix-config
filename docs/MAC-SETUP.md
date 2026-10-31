# Mac setup

How to take a Mac from nothing, or from an existing install, to an activated
nix-darwin config, and the steps Nix cannot do for you afterwards. The
README covers the one-line path for a brand-new Mac.

## Fresh install

`scripts/bootstrap.sh` installs the Xcode CLT and Nix, validates the host,
builds, and activates. It is idempotent.

```bash
git clone https://github.com/hodgesd/nix-config.git ~/nix-config
cd ~/nix-config && ./scripts/bootstrap.sh <hostname>
```

`<hostname>` must be a darwin host in `lib/machines.nix`. The script infers
it from `hostname -s` when omitted. To set the Mac's name to match first:

```bash
./scripts/set_mac_name.sh
```

Expect 15 to 30 minutes. Then restart your shell with `exec zsh`.

## Existing Mac with apps and data to keep

Do these before running bootstrap:

1. Take a Time Machine backup.
2. List the apps at risk:
   ```bash
   ./scripts/pre_install_audit.sh
   ```
3. Add the apps you want kept to `hosts/common/darwin/homebrew.nix`, and set
   `onActivation.cleanup = "none"` while migrating so nothing is removed.

After the first good switch, find stragglers and then restore cleanup:

```bash
./scripts/find_unmanaged_apps.sh
```

## After the first switch

These are one-time toggles that Nix cannot set.

**Wallpaper rotation.** Every Mac selects `~/Documents/Wallpapers/`
(iCloud-synced) as the wallpaper source through desktoppr, once per path
(`modules/wallpaper.nix`). A host opts out with
`majordouble.wallpaper.enable = false`. macOS 14+ has no scriptable way to
turn on rotation, so do it by hand: System Settings → Wallpaper → Change
picture, pick the interval, and enable Show on all Spaces if offered. Later
switches leave it alone. If you toggled it before the first switch, it gets
reset once, so toggle it again. A Mac without the folder or without the
desktoppr cask logs a warning at activation and is left alone.

**Reduce transparency.** System Settings → Accessibility → Display → Reduce
transparency. Glass menus let windows behind SwiftBar menus show through as
light and dark patches. It is not set in Nix because writing
`com.apple.universalaccess` needs Full Disk Access for the terminal, and
without it the switch aborts at "user defaults".

**Hotkeys (skhd and Karabiner-Elements).**

1. Launch Karabiner-Elements: `open -a Karabiner-Elements`.
2. System Settings → Privacy & Security → Accessibility: enable `skhd` and
   Karabiner-Elements.
3. Enable Launch at login in Karabiner-Elements preferences.
4. skhd starts at activation. If it did not, run
   `/opt/homebrew/bin/skhd --start-service`.
5. Test with `shift + ctrl + alt + y`, which creates `~/skhd-test.log`.

**Apps.**

- Launch at login: Raycast, Rectangle, SwiftBar, Ice, Reminders Menubar.
- Reminders Menubar: bind `meh-r`.
- iStat Menus: add the registration key.

## Helper scripts

| Script | When |
|---|---|
| `scripts/bootstrap.sh` | fresh Mac to activated nix-darwin |
| `scripts/set_mac_name.sh` | set the hostname to match the registry |
| `scripts/pre_install_audit.sh` | before nix-darwin is installed |
| `scripts/find_unmanaged_apps.sh` | after, to find apps Nix does not manage |
