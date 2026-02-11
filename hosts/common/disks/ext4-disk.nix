# Simple ext4 disk layout for cloud VMs and KVM guests.
# `...` is needed because disko passes diskoFile
{
  disk ? "/dev/vda",
  ...
}:
{
  disko.devices = {
    disk = {
      main = {
        device = disk;
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              priority = 1;
              name = "EFI";
              start = "1MiB";
              end = "512MiB";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [
                  "fmask=0077"
                  "dmask=0077"
                ];
              };
            };
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };
    };
  };
}
