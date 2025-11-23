# Network Storage Auto-Configuration for Darwin
# This optional module automatically enables network storage services based on
# configurations in nix-secrets. Just import this file in your Darwin host config.
#
# Usage:
#   imports = [ "hosts/common/optional/network-storage-darwin.nix" ];
#
# The module will:
# 1. Read networkStorageInfo.${hostname} from nix-secrets
# 2. Auto-enable Samba client if enable = true in the secrets
# 3. Automatically configure SOPS secrets for all SMB servers
# 4. Apply any extraConfig defined here for common, non-sensitive settings
{
  config,
  inputs,
  lib,
  ...
}:
let
  hostname = config.hostSpec.hostName;
  networkStorageInfo = inputs.nix-secrets.networkStorageInfo or { };
  hostConfig = networkStorageInfo.${hostname} or { };

  clientConfig = hostConfig.client or { };
  sambaConfig = clientConfig.samba or null;

  # Extract all server names from samba configuration
  sambaServers = if sambaConfig != null then builtins.attrNames (sambaConfig.servers or { }) else [ ];
in
{
  # Auto-enable services based on nix-secrets configuration
  networkStorage = {
    # Client auto-enable
    client = {
      samba.enable = lib.mkDefault (sambaConfig.enable or false);

      # Common client mount options (applies to all mounts)
      # These will be added to options specified in nix-secrets

      # Example Samba mount options for Darwin:
      # samba.extraOptions = [
      #   # Darwin-specific mount_smbfs options if needed
      # ];

      # Example: Customize health check interval
      # samba.healthCheckInterval = 600;  # 10 minutes
    };
  };

  # Automatically configure SOPS secrets for all SMB servers
  sops.secrets = lib.mkIf (sambaConfig.enable or false) (
    lib.listToAttrs (
      map (serverName: {
        name = "samba-${serverName}";
        value = {
          sopsFile = lib.mkDefault (inputs.nix-secrets + "/secrets/${hostname}.yaml");
          key = "samba/${serverName}/password";
          # Ensure the user running the launchd agent can read the credentials
          owner = config.hostSpec.username;
        };
      }) sambaServers
    )
  );
}
