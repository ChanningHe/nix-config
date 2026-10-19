# Prometheus node + process exporters (official NixOS modules).
#
# Importing this file runs both exporters on the host:
#   - node exporter: standard node metrics (CPU, memory, disk, network,
#     systemd, hwmon, ...) at :29100/metrics.
#   - process exporter (ncabatoff/process-exporter): per-process-group metrics
#     (CPU, memory, IO, threads, fds, ...) read from /proc at :29256/metrics.
#     By default every process is grouped by its command name (comm), which
#     keeps cardinality bounded. Without any process_names nothing would be
#     exported.
#
# Optional per-host overrides live in nix-secrets:
#   serviceInfo.<hostName>.node-exporter = {
#     port = 29100;                           # default
#     listenAddress = "0.0.0.0";              # default
#     enabledCollectors = [ "systemd" ];      # extra collectors on top of defaults
#     disabledCollectors = [ ];               # collectors to turn off
#     extraFlags = [                          # raw CLI flags
#       "--collector.filesystem.mount-points-exclude=^/(dev|proc|sys|var/lib/(docker|containers|incus)|run/containerd)($|/)"
#     ];
#   };
#   serviceInfo.<hostName>.process-exporter = {
#     port = 29256;                           # default
#     listenAddress = "0.0.0.0";              # default
#     processNames = [                        # replaces the default grouping
#       { name = "{{.Comm}}"; cmdline = [ ".+" ]; }
#     ];
#     extraFlags = [ "--threads=false" ];     # raw CLI flags
#   };
{
  config,
  ...
}:
let
  hostname = config.hostSpec.hostName;
  hostServices = config.hostSpec.serviceInfo.${hostname} or { };
  cfg = hostServices.node-exporter or { };
  processCfg = hostServices.process-exporter or { };

  # docker/podman/incus bind-mount piles of overlay/tmpfs filesystems into
  # /proc/mounts.
  defaultExtraFlags = [
    (
      "--collector.filesystem.mount-points-exclude="
      + "^/(dev|proc|sys|var/lib/(docker|containers|incus)/.+|run/(containerd|docker)/.+)($|/)"
    )
  ];

  defaultProcessNames = [
    {
      name = "{{.Comm}}";
      cmdline = [ ".+" ];
    }
  ];
in
{
  services.prometheus.exporters.node = {
    enable = true;
    listenAddress = cfg.listenAddress or "0.0.0.0";
    port = cfg.port or 29100;
    #openFirewall = true;
    enabledCollectors =
      cfg.enabledCollectors or [
        "systemd"
      ];
    disabledCollectors = cfg.disabledCollectors or [ "btrfs" ];
    extraFlags = defaultExtraFlags ++ (cfg.extraFlags or [ ]);
  };

  services.prometheus.exporters.process = {
    enable = true;
    listenAddress = processCfg.listenAddress or "0.0.0.0";
    port = processCfg.port or 29256;
    #openFirewall = true;
    settings.process_names = processCfg.processNames or defaultProcessNames;
    extraFlags = processCfg.extraFlags or [ ];
  };
}
