# GRUB boot configuration for ZFS mirror disk layout.
# Dual ESP at /boot1 and /boot2, with ZFS support.
{ pkgs, ... }:
{
  boot.loader.systemd-boot.enable = false;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.package = pkgs.zfs;
  boot.loader.timeout = 3;
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    zfsSupport = true;
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
