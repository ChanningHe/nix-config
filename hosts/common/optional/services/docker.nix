{
  config,
  lib,
  ...
}:
let
  hostname = config.hostSpec.hostName;
  dockerConfig = config.hostSpec.serviceInfo.${hostname}.docker or { };
in
{
  virtualisation.docker = {
    enable = lib.mkDefault true;
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
}
