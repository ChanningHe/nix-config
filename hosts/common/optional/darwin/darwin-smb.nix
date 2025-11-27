# darwin-nix SMB Auto-Mounter Configuration
#
# Automatically enables SMB mounting for Darwin hosts based on nix-secrets.
# Uses macOS native osascript for seamless Finder integration.
#
# Usage:
#   imports = [ "hosts/common/optional/darwin-smb.nix" ];
#
# Features:
# - Single unified script handles all mount points
# - Passwords stored in macOS Keychain (after first mount)
# - SOPS secrets optional (only for initial password provisioning)
# - Mounts appear in Finder sidebar automatically

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

  # Extract all server names for SOPS secret configuration
  sambaServers = if sambaConfig != null then builtins.attrNames (sambaConfig.servers or { }) else [ ];
in
{
  # Auto-enable based on nix-secrets
  networkStorage.client.samba = {
    enable = lib.mkDefault (sambaConfig.enable or false);

    # Customize check interval if needed (default: 300s = 5min)
    # checkInterval = 600;  # 10 minutes
  };

  # Configure SOPS secrets for initial password provisioning
  # After first successful mount, macOS Keychain takes over
  sops.secrets = lib.mkIf (sambaConfig.enable or false) (
    lib.listToAttrs (
      map (serverName: {
        name = "samba-${serverName}";
        value = {
          sopsFile = lib.mkDefault (inputs.nix-secrets + "/secrets/${hostname}.yaml");
          key = "samba/${serverName}/password";
          owner = config.hostSpec.username;
        };
      }) sambaServers
    )
  );
}
