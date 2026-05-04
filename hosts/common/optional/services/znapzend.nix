#   Bridges hostSpec.serviceInfo.<host>.znapzend to:
#   - upstream services.znapzend.*       via znapzendInfo.config
#   - znapzendSsh module (modules/hosts/nixos/znapzend) via znapzendInfo.ssh
{
  config,
  lib,
  inputs,
  ...
}:
let
  hostName = config.hostSpec.hostName;
  znapzendInfo = config.hostSpec.serviceInfo.${hostName}.znapzend;
  sshTargets = znapzendInfo.ssh.targets or { };
  sopsFile = "${builtins.toString inputs.nix-secrets}/secrets/${hostName}.yaml";
in
{
  imports = [
    (lib.custom.relativeToRoot "modules/hosts/nixos/znapzend")
  ];

  services.znapzend = znapzendInfo.config // {
    enable = true;
  };

  znapzendSsh = lib.mkIf (sshTargets != { }) {
    enable = true;
    targets = sshTargets;
    identity = {
      inherit sopsFile;
    }
    // (znapzendInfo.ssh.identity or { });
  };
}
