{
  config,
  lib,
  pkgs,
  ...
}:
let
  hostname = config.hostSpec.hostName;
  cfg = config.hostSpec.serviceInfo.${hostname}.ipmi-exporter or { };
in
{
  # CLI for talking to the BMC (local /dev/ipmi0 or remote -H)
  environment.systemPackages = [ pkgs.ipmitool ];

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
    # configFile = cfg.configFile or (pkgs.writeText "ipmi-exporter-local.yml" ''
    #   modules:
    #     default:
    #       collectors:
    #         - ipmi
    #         - dcmi
    #         - bmc
    #         - chassis
    #       custom_args:
    #         ipmi:
    #           - "--sdr-cache-recreate"
    # '');
    extraFlags = cfg.extraFlags or [ ];
  };

  # nixpkgs' hardening for the exporter unit sets PrivateDevices=true, which
  # mounts a private /dev without /dev/ipmi0 -- freeipmi then fails with
  # "could not find inband device".
  systemd.services.prometheus-ipmi-exporter.serviceConfig.PrivateDevices = lib.mkForce false;
}
