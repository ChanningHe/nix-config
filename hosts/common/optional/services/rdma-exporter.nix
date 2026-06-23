# Prometheus RDMA exporter (yuuki/rdma_exporter).
#
# Importing this file runs the exporter on the host. It reads RDMA metrics from
# /sys/class/infiniband (and optionally netdev ethtool stats for RoCE), so it
# only makes sense on hosts with InfiniBand/RoCE HCAs.
#
# Optional per-host overrides live in nix-secrets:
#   serviceInfo.<hostName>.rdma-exporter = {
#     listenAddress = ":9879";   # default
#     extraArgs = "--exclude-devices=mlx5_0";
#   };
{
  config,
  lib,
  pkgs,
  ...
}:
let
  hostname = config.hostSpec.hostName;
  cfg = config.hostSpec.serviceInfo.${hostname}.rdma-exporter or { };
  listenAddress = cfg.listenAddress or ":9879";
  extraArgs = cfg.extraArgs or "";
in
{
  systemd.services.rdma-exporter = {
    description = "Prometheus RDMA exporter";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];

    serviceConfig = {
      ExecStart =
        "${lib.getExe pkgs.rdma-exporter} --listen-address=${listenAddress}"
        + lib.optionalString (extraArgs != "") " ${extraArgs}";
      Restart = "on-failure";
      RestartSec = "5s";

      # Unprivileged: sysfs RDMA counters are world-readable. ethtool netdev
      # stats (RoCE) need CAP_NET_ADMIN; granted ambiently so the exporter can
      # collect them without running as full root.
      DynamicUser = true;
      AmbientCapabilities = [ "CAP_NET_ADMIN" ];
      CapabilityBoundingSet = [ "CAP_NET_ADMIN" ];

      # Hardening. ProtectSystem=strict keeps /sys readable (only /dev,/proc,/sys
      # stay mounted), which is all the exporter needs.
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_NETLINK"
      ];
      RestrictNamespaces = true;
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
    };
  };
}
