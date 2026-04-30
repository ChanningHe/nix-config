{ pkgs, ... }:
{
  # CLI for talking to the BMC (local /dev/ipmi0 or remote -H)
  environment.systemPackages = [ pkgs.ipmitool ];

  # In-band access to the BMC requires these kernel modules.
  # Without them ipmitool only works in remote (-I lanplus) mode.
  boot.kernelModules = [
    "ipmi_devintf"   # /dev/ipmi0 character device
    "ipmi_si"        # KCS/SMIC/BT system interface (most servers)
    "ipmi_msghandler"
  ];
}
