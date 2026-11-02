# nixos-facter defaults. Inert until a host sets `facter.reportPath`.
{ inputs, lib, ... }:
{
  imports = [ inputs.nixos-facter-modules.nixosModules.facter ];

  facter.detected = {
    dhcp.enable = false; # networking is always declared explicitly
    bluetooth.enable = lib.mkDefault false;
    graphics.enable = lib.mkDefault false; # depends on a monitor at scan time
    graphics.amd.enable = lib.mkDefault false;
  };
}
