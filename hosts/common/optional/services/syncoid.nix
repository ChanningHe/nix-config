#   Bridges hostSpec.serviceInfo.<host>.syncoid to the syncoidPull module
#   (modules/hosts/nixos/syncoid).
#
# Required sops secret (in host's yaml file):
# - syncoid/ssh_private_key: ed25519 key authorized on every source
{
  config,
  lib,
  ...
}:
let
  hostName = config.hostSpec.hostName;
  syncoidInfo = config.hostSpec.serviceInfo.${hostName}.syncoid;
  mail = config.hostSpec.serviceInfo.mail or { enable = false; };
in
{
  syncoidPull = {
    enable = true;
    inherit (syncoidInfo) sources;
    sshKey.sopsFile = "${config.hostSpec.sopsDir}/${hostName}.yaml";
    notify = lib.mkIf mail.enable {
      enable = true;
      inherit (mail) from recipients;
    };
  }
  // lib.optionalAttrs (syncoidInfo ? interval) { inherit (syncoidInfo) interval; }
  // lib.optionalAttrs (syncoidInfo ? pruneInterval) { inherit (syncoidInfo) pruneInterval; };
}
