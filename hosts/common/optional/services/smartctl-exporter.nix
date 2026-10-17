# Prometheus smartctl exporter (official NixOS module).
#
# Importing this file runs prometheus-community/smartctl_exporter on the host,
# exposing S.M.A.R.T. metrics for SATA/SAS/NVMe disks at :29633/metrics.
# Disks are autodiscovered unless `devices` is set.
#
# Optional per-host overrides live in nix-secrets:
#   serviceInfo.<hostName>.smartctl-exporter = {
#     port = 29633;                           # default
#     listenAddress = "0.0.0.0";              # default
#     devices = [ "/dev/sda" "/dev/nvme0" ];  # default: autodiscover
#     maxInterval = "60s";                    # default; min time between disk queries
#     extraFlags = [                          # raw CLI flags
#       "--smartctl.device-exclude=^(loop|zd)"
#     ];
#   };
{
  config,
  ...
}:
let
  hostname = config.hostSpec.hostName;
  cfg = config.hostSpec.serviceInfo.${hostname}.smartctl-exporter or { };
in
{
  services.prometheus.exporters.smartctl = {
    enable = true;
    listenAddress = cfg.listenAddress or "0.0.0.0";
    port = cfg.port or 29633;
    #openFirewall = true;
    devices = cfg.devices or [ ];
    maxInterval = cfg.maxInterval or "60s";
    extraFlags = cfg.extraFlags or [ ];
  };
}
