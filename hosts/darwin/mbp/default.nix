# Host-specific configuration for mbp (MacBook Pro, the daily driver).
{username, ...}: {
  imports = [./backup.nix];

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
    # cprt.1d.py / news.6hr.py plugins, which read /run/secrets/cprt-feed-url.
    # Moved out of the public swiftbar_plugins repo 2026-10-17; the old key is
    # still in that repo's history until it's regenerated on the forum.
    secrets.cprt-feed-url = {
      owner = username;
      mode = "0400";
    };
  };
}
