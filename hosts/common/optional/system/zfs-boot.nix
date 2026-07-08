# GRUB boot for ZFS layouts. Handles both single-disk and mirror.
#
# Whether the second ESP (/boot2) is appended is driven by `hostSpec.zfsMirror`:
#   - Hosts going through `lib.custom.bootDiskLayout` get it set automatically
#     from the `layout` argument.
#   - Hosts that import this file directly declare it themselves in `hostSpec`.
{
  pkgs,
  lib,
  config,
  ...
}:
let
  # ARM UEFI boards (e.g. Ampere/Deissneri) have unreliable NVRAM boot entries.
  # Skip writing efivars and install to the UEFI removable fallback path instead.
  isAarch64 = pkgs.stdenv.hostPlatform.isAarch64;
  mirror = config.hostSpec.zfsMirror;
in
{
  boot.loader.systemd-boot.enable = false;
  boot.loader.efi.canTouchEfiVariables = !isAarch64;
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
    efiInstallAsRemovable = isAarch64;
    mirroredBoots = [
      {
        devices = [ "nodev" ];
        path = "/boot1";
        efiSysMountPoint = "/boot1";
      }
    ]
    ++ lib.optional mirror {
      devices = [ "nodev" ];
      path = "/boot2";
      efiSysMountPoint = "/boot2";
    };
  };
}
