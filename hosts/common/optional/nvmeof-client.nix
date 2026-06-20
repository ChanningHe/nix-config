# NVMe-oF Client Auto-Configuration
#
# Usage:
#   imports = [ "hosts/common/optional/nvmeof-client.nix" ];
#
# The module will:
# 1. Read nvmeofInfo.${hostname} from nix-secrets
# 2. Auto-enable the NVMe-oF connect service if enable = true there
# 3. Apply common, non-sensitive mount/connect options defined here
#
{
  config,
  inputs,
  lib,
  ...
}:
let
  hostname = config.hostSpec.hostName;
  nvmeofInfo = inputs.nix-secrets.nvmeofInfo or { };
  hostConfig = nvmeofInfo.${hostname} or { };
in
{
  nvmeofStorage = {
    enable = lib.mkDefault (hostConfig.enable or false);

    # Common, host-agnostic mount options for every NVMe-oF filesystem.
    # noatime: skip atime metadata writes -- pointless on fast fabric storage.
    extraMountOptions = [
      "noatime"
    ];

    # Common args appended to every `nvme connect` (host-agnostic, non-secret).
    # extraConnectArgs = [ ];
  };
}
