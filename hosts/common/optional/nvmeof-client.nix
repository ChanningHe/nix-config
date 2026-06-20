# Auto-enable NVMe-oF from nix-secrets. Import in a host to opt in.
{
  config,
  inputs,
  lib,
  ...
}:
let
  hostname = config.hostSpec.hostName;
  hostConfig = inputs.nix-secrets.nvmeofInfo.${hostname} or { };
in
{
  nvmeofStorage = {
    enable = lib.mkDefault (hostConfig.enable or false);
    extraMountOptions = [ "noatime" ];
  };
}
