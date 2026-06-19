# Boot-disk layout helper, exposed as `lib.custom.bootDiskLayout`.
#
# Maps a disk layout to the modules a host needs for `imports`: the disko module,
# the boot disk device paths (via _module.args, consumed by the disko layout
# files), the matching disko layout, and the matching bootloader.
#
# Called from a host's `imports` so the layout stays out of the module fixpoint
# (choosing `imports` from `config.*` would infinite-recurse). spawn.sh sets
# `layout` and back-fills `disk` (and `disk2` for zfs-mirror).
{ lib }:
let
  relativeToRoot = lib.path.append ../.;
in
inputs:
{
  layout,
  disk ? "/dev/vda",
  disk2 ? "/dev/vdb",
}:
let
  diskoFor = {
    ext4 = relativeToRoot "hosts/common/disks/ext4-disk.nix";
    btrfs = relativeToRoot "hosts/common/disks/btrfs-disk.nix";
    zfs = relativeToRoot "hosts/common/disks/zfs-disk.nix";
    zfs-mirror = relativeToRoot "hosts/common/disks/zfs-mirror-disk.nix";
  };
  bootFor = {
    ext4 = relativeToRoot "hosts/common/optional/system/systemd-boot.nix";
    btrfs = relativeToRoot "hosts/common/optional/system/systemd-boot.nix";
    zfs = relativeToRoot "hosts/common/optional/system/zfs-boot.nix";
    zfs-mirror = relativeToRoot "hosts/common/optional/system/zfs-mirror-boot.nix";
  };
in
[
  inputs.disko.nixosModules.disko
  {
    _module.args = {
      inherit disk;
      primaryDisk = disk;
      secondaryDisk = disk2;
    };
  }
  diskoFor.${layout}
  bootFor.${layout}
]
