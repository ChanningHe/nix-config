{ config, lib, pkgs, ... }:
{
  # Not use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = false;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.package = pkgs.zfs;
  boot.loader.timeout = 3;
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    zfsSupport = true;
    #efi.canTouchEfiVariables = true;
    mirroredBoots = [
	    { devices = [ "nodev" ]; path = "/boot1"; efiSysMountPoint = "/boot1"; }
	    { devices = [ "nodev" ]; path = "/boot2"; efiSysMountPoint = "/boot2"; }
    ];
  };

}
