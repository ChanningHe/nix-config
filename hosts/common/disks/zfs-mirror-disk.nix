# ZFS mirror disk layout for dual-disk servers.
# Both disks MUST be different devices for ZFS mirror to work.
# Use /dev/disk/by-id/ paths for stable device identification.
# `...` is needed because disko passes diskoFile
{
  primaryDisk ? "/dev/vda",
  secondaryDisk ? "/dev/vdb",
  ...
}:
{
  disko.devices = {
    disk = {
      disk1 = {
        device = primaryDisk;
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              priority = 1;
              name = "EFI";
              start = "1MiB";
              end = "1GiB";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot1";
                mountOptions = [
                  "fmask=0077"
                  "dmask=0077"
                  "iocharset=iso8859-1"
                ];
              };
            };
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "rpool";
              };
            };
          };
        };
      };
      disk2 = {
        device = secondaryDisk;
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              priority = 1;
              name = "EFI";
              start = "1MiB";
              end = "1GiB";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot2";
                mountOptions = [
                  "fmask=0077"
                  "dmask=0077"
                  "iocharset=iso8859-1"
                ];
              };
            };
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "rpool";
              };
            };
          };
        };
      };
    };
    zpool = {
      rpool = {
        type = "zpool";
        mode = "mirror";
        options = {
          ashift = "12";
          autotrim = "on";
        };
        rootFsOptions = {
          acltype = "posixacl";
          canmount = "off";
          dnodesize = "auto";
          normalization = "formD";
          relatime = "on";
          xattr = "sa";
          mountpoint = "none";
          primarycache = "metadata";
        };
        datasets = {
          root = {
            type = "zfs_fs";
            mountpoint = "/";
            options = {
              canmount = "noauto";
              mountpoint = "legacy";
            };
          };
          home = {
            type = "zfs_fs";
            mountpoint = "/home";
            options = {
              mountpoint = "legacy";
            };
          };
        };
      };
    };
  };
}
