# NVMe-over-Fabrics (NVMe-oF) CLIENT / initiator module for NixOS.
#
# Reads its configuration from nix-secrets (nvmeofInfo.${hostname}) and:
#   1. loads the right kernel transport modules (nvme_rdma / nvme_tcp)
#   2. pins a stable host NQN + host ID under /etc/nvme
#   3. runs one oneshot `nvme connect` per boot, tolerant of a down target
#   4. generates fileSystems entries wired to wait for the connect service
{
  config,
  lib,
  inputs,
  pkgs,
  ...
}:
let
  cfg = config.nvmeofStorage;

  nvmeofInfo = inputs.nix-secrets.nvmeofInfo or { };
  hostConfig = nvmeofInfo.${cfg.hostname} or { };

  enabled = cfg.enable && hostConfig != { };

  defaultTransport = hostConfig.transport or "rdma";
  targets = hostConfig.targets or [ ];

  transportOf = t: t.transport or defaultTransport;

  # Resolve a target to a STABLE block-device path for mounting. Never reference
  # /dev/nvmeXnY directly: enumeration order is not stable across reboots. Order
  # of preference (most robust first):
  #   label         -> /dev/disk/by-label/<x>   (fs label you set at mkfs; survives
  #                                               target re-export, recommended)
  #   fsUuid        -> /dev/disk/by-uuid/<x>     (fs UUID from mkfs)
  #   namespaceUuid -> /dev/disk/by-id/nvme-uuid.<x>  (UUID the kernel derives from
  #                                                    the namespace, see `nvme list`)
  #   serial        -> /dev/disk/by-id/nvme-<x>  (target model+serial)
  #   device        -> raw path, used verbatim (escape hatch)
  deviceOf =
    t:
    if (t.label or null) != null then
      "/dev/disk/by-label/${t.label}"
    else if (t.fsUuid or null) != null then
      "/dev/disk/by-uuid/${t.fsUuid}"
    else if (t.namespaceUuid or null) != null then
      "/dev/disk/by-id/nvme-uuid.${t.namespaceUuid}"
    else if (t.serial or null) != null then
      "/dev/disk/by-id/nvme-${t.serial}"
    else if (t.device or null) != null then
      t.device
    else
      throw "nvmeofStorage: target '${t.nqn}' has a mountPoint but no way to find its device (set label/fsUuid/namespaceUuid/serial/device).";

  # Kernel transport modules actually used, plus the common fabrics core.
  transports = lib.unique (map transportOf targets);
  transportModules = [
    "nvme_fabrics"
  ]
  ++ lib.optional (lib.elem "rdma" transports) "nvme_rdma"
  ++ lib.optional (lib.elem "tcp" transports) "nvme_tcp";

  # `nvme connect` invocation for one target. Long flags for readability.
  # `|| true`: re-running for an already-connected subsystem (rebuild switch,
  # service restart) returns non-zero -- not a failure. Real success is decided
  # by the device symlink appearing below.
  connectOne = t: ''
    echo "nvme-oF: connecting ${t.nqn} via ${transportOf t} @ ${t.traddr}:${t.trsvcid or "4420"}"
    ${pkgs.nvme-cli}/bin/nvme connect \
      --transport=${transportOf t} \
      --traddr=${t.traddr} \
      --trsvcid=${t.trsvcid or "4420"} \
      --nqn=${t.nqn} \
      --hostnqn=${hostConfig.hostNqn} \
      --hostid=${hostConfig.hostId} \
      --ctrl-loss-tmo=${toString (t.ctrlLossTmo or (-1))} \
      --reconnect-delay=${toString (t.reconnectDelay or 10)} \
      ${lib.optionalString (t ? nrIoQueues) "--nr-io-queues=${toString t.nrIoQueues} "}\
      ${lib.concatStringsSep " " (t.connectArgs or [ ])} \
      ${lib.concatStringsSep " " cfg.extraConnectArgs} || true
  ''; # noqa

  connectScript = pkgs.writeShellScript "nvmeof-connect" ''
    set -u
    ${lib.concatMapStringsSep "\n" connectOne targets}

    # Let udev finish publishing the new block devices + by-id/by-label symlinks
    # before the dependent .mount units try to resolve their device. Identifier-
    # agnostic, so it works whether you mount by label, uuid, or serial.
    ${pkgs.systemd}/bin/udevadm settle --timeout=20 || true
  '';

  # Only targets that ask to be mounted get a fileSystems entry. A target with
  # no mountPoint is connected (raw block device) but left for the host to use
  # directly (e.g. as a ZFS vdev).
  mountTargets = lib.filter (t: (t.mountPoint or null) != null) targets;
in
{
  options.nvmeofStorage = {
    hostname = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      description = "Hostname to look up in nvmeofInfo. Defaults to the system hostname.";
    };

    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Connect NVMe-oF targets from nix-secrets.
        Configuration must exist at nvmeofInfo.''${hostname} in nix-secrets.
      '';
    };

    extraConnectArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra arguments appended to every `nvme connect` invocation.";
      example = [ "--keep-alive-tmo=5" ];
    };

    extraMountOptions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra mount options added to every generated fileSystems entry.";
      example = [ "noatime" ];
    };
  };

  config = lib.mkMerge [
    (lib.mkIf enabled {
      boot.kernelModules = transportModules;

      environment.systemPackages = [ pkgs.nvme-cli ];

      # Stable initiator identity. The target's ACL keys off the host NQN, so it
      # must be deterministic and survive reboots -- never let nvme-cli generate
      # a random one at runtime.
      environment.etc."nvme/hostnqn".text = "${hostConfig.hostNqn}\n";
      environment.etc."nvme/hostid".text = "${hostConfig.hostId}\n";

      systemd.services.nvmeof-connect = {
        description = "Connect NVMe-oF targets for ${cfg.hostname}";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = connectScript;
          # Disconnect cleanly on stop so a rebuild switch / shutdown doesn't
          # leave dangling controllers.
          ExecStop = "${pkgs.nvme-cli}/bin/nvme disconnect-all";
        };
      };

      fileSystems = builtins.listToAttrs (
        map (t: {
          name = t.mountPoint;
          value = {
            device = deviceOf t;
            fsType = t.fsType or "xfs";
            options = [
              "_netdev"
              "x-systemd.requires=nvmeof-connect.service"
              "x-systemd.after=nvmeof-connect.service"
              "x-systemd.device-timeout=15s"
            ]
            ++ (t.options or [ ])
            ++ cfg.extraMountOptions;
          };
        }) mountTargets
      );
    })

    # Warn loudly if switched on with nothing to do -- mirrors network-storage.
    (lib.mkIf (cfg.enable && hostConfig == { }) {
      warnings = [
        ''
          nvmeofStorage.enable is true but no NVMe-oF configuration found for host '${cfg.hostname}'.
          Expected configuration at: nvmeofInfo.${cfg.hostname} in nix-secrets.
        ''
      ];
    })
  ];
}
