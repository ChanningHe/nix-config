# Auto-enable NVMe-oF from nix-secrets. Import in a host to opt in.
{
  config,
  lib,
  ...
}:
let
  hostname = config.hostSpec.hostName;
  hostConfig = config.hostSpec.nvmeofInfo.${hostname} or { };
in
{
  nvmeofStorage = {
    enable = lib.mkDefault (hostConfig.enable or false);
    extraMountOptions = [ "noatime" ];
  };
}
