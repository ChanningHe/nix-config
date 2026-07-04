{
  config,
  lib,
  inputs,
  utils,
  ...
}:
let
  hostname = config.hostSpec.hostName;
  dockerConfig = config.hostSpec.serviceInfo.${hostname}.docker or { };

  # Make docker wait for the network storage its containers bind, so binds never
  # resolve to empty dirs. Gate on the module flags (true only when the .mount
  # units actually exist); escapeSystemdPath turns mountPoints into unit names.
  useNfs = config.networkStorage.client.nfs.enable or false;
  useNvmeof = config.nvmeofStorage.enable or false;

  toUnits = mountPoints: map (mp: "${utils.escapeSystemdPath mp}.mount") mountPoints;

  nfsUnits = toUnits (
    lib.optionals useNfs (
      map (m: m.mountPoint) (inputs.nix-secrets.networkStorageInfo.${hostname}.client.nfs.mounts or [ ])
    )
  );

  nvmeofUnits = toUnits (
    lib.optionals useNvmeof (
      map (t: t.mountPoint) (
        lib.filter (t: (t.mountPoint or null) != null) (
          inputs.nix-secrets.nvmeofInfo.${hostname}.targets or [ ]
        )
      )
    )
  );
in
{
  virtualisation.docker = {
    enable = lib.mkDefault true;
    logDriver = "local";
    daemon.settings = {
      experimental = true;
      default-address-pools =
        dockerConfig.defaultAddressPools or [
          {
            # 172.16-31.0.0/16
            base = "172.17.0.0/16";
            size = 24;
          }
        ];
    };
  };

  systemd.services.docker = lib.mkMerge [
    # NVMe-oF: single critical block volume -> hard require (no start on empty).
    (lib.mkIf (nvmeofUnits != [ ]) {
      after = nvmeofUnits;
      requires = nvmeofUnits;
    })

    # NFS: order + trigger, but soft (`wants`) -- one dead share shouldn't down
    # docker, and a hard hold would defeat the autofs idle-unmount workaround.
    (lib.mkIf (nfsUnits != [ ]) {
      after = nfsUnits;
      wants = nfsUnits;
    })
  ];
}
