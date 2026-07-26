# UNAS "Data" share mounted for MeTube downloads (Data/Videos/MeTube).
# Automount (no idle-timeout): path access triggers the mount, boot
# never blocks on the NAS, and docker's bind of the path mounts the
# real fs. uid/gid 1000 = the container user MeTube writes as.
#
# NAS IP 192.168.1.142 also appears in backup.nix (backups share).
{...}: {
  fileSystems."/mnt/data" = {
    device = "//192.168.1.142/Data";
    fsType = "cifs";
    options = [
      "credentials=/etc/nas-backup.credentials"
      "vers=3.0"
      "uid=1000"
      "gid=1000"
      "file_mode=0664"
      "dir_mode=0775"
      "noauto"
      "x-systemd.automount"
      "_netdev"
      "nofail"
    ];
  };
}
