# Enable promiscuous mode on the ConnectX-5 VF passed through to this guest.
#
# Done via udev so promisc is set at boot AND on hotplug, regardless of the
# interface name the kernel assigns.
{ pkgs, ... }:
{
  services.udev.extraRules = ''
    ACTION=="add|change", SUBSYSTEM=="net", ATTRS{vendor}=="0x15b3", ATTRS{device}=="0x1018", RUN+="${pkgs.iproute2}/bin/ip link set %k promisc on"
  '';
}
