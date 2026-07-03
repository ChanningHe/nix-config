{ config, pkgs, ... }:
let
  hostname = config.hostSpec.hostName;
  cfg = config.hostSpec.serviceInfo.${hostname}.ipmi-exporter or { };
in
{
  # CLI for talking to the BMC (local /dev/ipmi0 or remote -H)
  environment.systemPackages = [ pkgs.ipmitool ];

  # In-band access to the BMC requires these kernel modules.
  # Without them ipmitool only works in remote (-I lanplus) mode.
  boot.kernelModules = [
    "ipmi_devintf" # /dev/ipmi0 character device
    "ipmi_si" # KCS/SMIC/BT system interface (most servers)
    "ipmi_msghandler"
  ];

  # Prometheus IPMI exporter (prometheus-community/ipmi_exporter, via FreeIPMI).
  services.prometheus.exporters.ipmi = {
    enable = true;
    listenAddress = cfg.listenAddress or "0.0.0.0";
    port = cfg.port or 29290;
    #openFirewall = true;
    configFile = cfg.configFile or null;
    extraFlags = cfg.extraFlags or [ ];
  };
}
