# Linux-specific home-manager configuration
# This file contains configurations that only work on Linux systems
{
  pkgs,
  ...
}:
{
  # Linux-specific packages
  home.packages = with pkgs; [
    pciutils # PCI device utilities (lspci)
    usbutils # USB device utilities (lsusb)
    lm_sensors # Hardware monitoring
    # sysstat # System statistics
    traceroute
  ];

  services.ssh-agent.enable = true;
  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";
}
