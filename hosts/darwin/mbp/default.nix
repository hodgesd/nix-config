# Host-specific configuration for mbp (MacBook Pro, the daily driver).
{username, ...}: {
  imports = [./backup.nix];

  # The CPRT plugin needs the two forum feed secrets below, which only this
  # host has; repoFiles is a list, so this appends to the shared plugin set.
  home-manager.users.${username}.programs.swiftbar.repoFiles = ["cprt.1h.py"];

  # sops on this host: the NAS credentials for backup.nix. Decrypted at
  # activation using the mbp's SSH host key (the .sops.yaml host_mbp
  # recipient). Reinstalling macOS regenerates that key — re-derive it with
  # `ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub`, update .sops.yaml, then
  # `sops updatekeys secrets/mbp.yaml`.
  sops = {
    defaultSopsFile = ../../../secrets/mbp.yaml;
    age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
    # Readable by the user, not just root: the backup runs as a launchd
    # *user* agent (it reads files in the user's home), so the sops default
    # of root-only would fail only at runtime, long after activation.
    secrets.nas-backup-credentials = {
      owner = username;
      mode = "0400";
    };
    # Chief Pilots Forum RSS URL (member id + feed key) for the swiftbar
    # cprt.1h.py / news.6hr.py plugins, which read /run/secrets/cprt-feed-url.
    # Moved out of the public swiftbar_plugins repo 2026-10-17; the old key is
    # still in that repo's history until it's regenerated on the forum.
    secrets.cprt-feed-url = {
      owner = username;
      mode = "0400";
    };
    # Second forum feed for the cprt plugin: the member's "My CPRT Replies"
    # activity stream (ownership "Content I have posted in", forum 5), whose
    # topic ids are subtracted from the latest-topics feed to list topics
    # still owed a reply. Same member id + key scheme as above.
    secrets.cprt-posted-feed-url = {
      owner = username;
      mode = "0400";
    };
  };
}
