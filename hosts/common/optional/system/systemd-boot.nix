# systemd-boot configuration for ext4 and btrfs disk layouts.
# Single /boot ESP partition.
{ lib, ... }:
{
  fileSystems."/boot".options = [ "umask=0077" ];
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = lib.mkDefault 3;
    consoleMode = lib.mkDefault "max";
  };
}
