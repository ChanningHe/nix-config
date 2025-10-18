{ config, lib, pkgs, ... }:
{
  services.tailscale = {
    enable = true;
  };

  #services.tailscale.interfaceName = "userspace-networking";

  services.networkd-dispatcher = {
    enable = true;
    rules."50-tailscale" = {
      onState = ["routable"];
      script = ''
        NETDEV=$(${pkgs.iproute2}/bin/ip -o route get 8.8.8.8 | ${pkgs.coreutils}/bin/cut -f 5 -d " ")
        ${pkgs.ethtool}/bin/ethtool -K "$NETDEV" rx-udp-gro-forwarding on rx-gro-list off
      '';
    };
  };

  environment.systemPackages = with pkgs; [
        ethtool
        networkd-dispatcher
   ];

  # Enable IP forwarding for Tailscale (use mkDefault to avoid conflicts)
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = lib.mkDefault 1;
    "net.ipv6.conf.all.forwarding" = lib.mkDefault 1;
  };
}
