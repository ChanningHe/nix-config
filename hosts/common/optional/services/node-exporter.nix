# Prometheus node exporter (official NixOS module).
#
# Importing this file runs the exporter on the host, exposing standard node
# metrics (CPU, memory, disk, network, systemd, hwmon, ...) at :9100/metrics.
#
# Optional per-host overrides live in nix-secrets:
#   serviceInfo.<hostName>.node-exporter = {
#     port = 9100;                            # default
#     listenAddress = "0.0.0.0";              # default
#     enabledCollectors = [ "systemd" ];      # extra collectors on top of defaults
#     disabledCollectors = [ ];               # collectors to turn off
#     extraFlags = [                          # raw CLI flags
#       "--collector.filesystem.mount-points-exclude=^/(dev|proc|sys|var/lib/(docker|containers|incus)|run/containerd)($|/)"
#     ];
#   };
{
  config,
  ...
}:
let
  hostname = config.hostSpec.hostName;
  cfg = config.hostSpec.serviceInfo.${hostname}.node-exporter or { };

  # docker/podman/incus bind-mount piles of overlay/tmpfs filesystems into
  # /proc/mounts.
  defaultExtraFlags = [
    (
      "--collector.filesystem.mount-points-exclude="
      + "^/(dev|proc|sys|var/lib/(docker|containers|incus)/.+|run/(containerd|docker)/.+)($|/)"
    )
  ];
in
{
  services.prometheus.exporters.node = {
    enable = true;
    listenAddress = cfg.listenAddress or "0.0.0.0";
    port = cfg.port or 29100;
    #openFirewall = true;
    enabledCollectors = cfg.enabledCollectors or [ ];
    disabledCollectors = cfg.disabledCollectors or [ ];
    extraFlags = defaultExtraFlags ++ (cfg.extraFlags or [ ]);
  };
}
