# WireGuard via wg-quick, driven by plain .conf files.
#
# Enabled per interface in nix-secrets network.nix:
#   networkInfo.hosts.<HostName>.wireguard.<iface> = { };
#   networkInfo.hosts.<HostName>.wireguard.<iface>.configFile = "/path/to/<iface>.conf";
# Default config path: /etc/wireguard/<iface>.conf
#
# Nix only handles boot-time startup; keys, peers and NAT (PostUp/PostDown)
# live in the .conf. The unit PATH already provides iptables and iproute2.
# The file is read at service start only: after editing it, run
#   systemctl restart wg-quick-<iface>
{
  config,
  lib,
  ...
}:
let
  hostName = config.hostSpec.hostName;
  hostNetwork = config.hostSpec.networkInfo.hosts.${hostName} or { };
  wgInterfaces = hostNetwork.wireguard or { };

  configFileOf = name: iface: iface.configFile or "/etc/wireguard/${name}.conf";
in
{
  config = lib.mkIf (wgInterfaces != { }) {
    networking.wg-quick.interfaces = lib.mapAttrs (name: iface: {
      configFile = configFileOf name iface;
    }) wgInterfaces;

    # The config may live on a ZFS dataset; don't start before it is mounted.
    systemd.services = lib.mapAttrs' (
      name: iface:
      lib.nameValuePair "wg-quick-${name}" {
        unitConfig.RequiresMountsFor = [ (configFileOf name iface) ];
      }
    ) wgInterfaces;

    # NAT is done in the .conf; forwarding must be on (mkDefault to avoid conflicts).
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = lib.mkDefault 1;
      "net.ipv6.conf.all.forwarding" = lib.mkDefault 1;
    };
  };
}
