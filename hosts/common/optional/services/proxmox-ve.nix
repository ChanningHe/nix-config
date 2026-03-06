# Proxmox VE Virtualization Platform
# This service provides a complete virtualization management solution
{
  config,
  lib,
  inputs,
  ...
}:
let
  hostName = config.hostSpec.hostName;
  hostProxmox = config.hostSpec.serviceInfo.${hostName}.proxmox-ve or { };
in
{
  imports = [
    inputs.proxmox-nixos.nixosModules.proxmox-ve
  ];

  # proxmox-nixos packages are not in nixpkgs; inject overlay locally
  nixpkgs.overlays = [ inputs.proxmox-nixos.overlays.x86_64-linux ];

  config = {
    # Configure from hostSpec if available
    services.proxmox-ve = {
      enable = lib.mkDefault (hostProxmox.enable or false);
      ipAddress = lib.mkDefault (hostProxmox.ipAddress or "");
      bridges = lib.mkDefault (hostProxmox.bridges or [ "vmbr0" ]);
    };

    # Enable IP forwarding when service is enabled
    boot.kernel.sysctl = lib.mkIf config.services.proxmox-ve.enable {
      "net.ipv4.ip_forward" = lib.mkDefault 1;
      "net.ipv6.conf.all.forwarding" = lib.mkDefault 1;
    };

    # Optionally open firewall ports for Proxmox web interface and API
    # Uncomment if you need external access to Proxmox
    # networking.firewall.allowedTCPPorts = lib.mkIf config.services.proxmox-ve.enable [ 8006 ];
  };
}
