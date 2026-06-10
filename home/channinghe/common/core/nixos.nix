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

  # For Zed Remote Server
  home.file.".zed_server" = {
    source = "${pkgs.zed-editor.remote_server}/bin";
    # keeps the folder writable, but symlinks the binaries into it
    recursive = true;
  };

  services.ssh-agent.enable = true;
  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";
}
