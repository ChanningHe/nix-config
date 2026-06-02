{
  pkgs,
  ...
}:
{
  # Not use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = false;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.package = pkgs.zfs;
  # New default from 26.11. Safe here: every ZFS host pins a stable networking.hostId,
  # so normal and post-crash reboots still import (hostid matches the machine). Only a
  # real hostid mismatch (reinstall / disk moved / VM clone) refuses import — exactly the
  # case where force-importing could corrupt a pool another system still owns.
  boot.zfs.forceImportRoot = false;
  boot.loader.timeout = 3;
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    zfsSupport = true;
    #efi.canTouchEfiVariables = true;
    mirroredBoots = [
      {
        devices = [ "nodev" ];
        path = "/boot1";
        efiSysMountPoint = "/boot1";
      }
      {
        devices = [ "nodev" ];
        path = "/boot2";
        efiSysMountPoint = "/boot2";
      }
    ];
  };

}
