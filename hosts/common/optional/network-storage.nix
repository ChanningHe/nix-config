# Network Storage Auto-Configuration
# This optional module automatically enables network storage services based on
# configurations in nix-secrets. Just import this file in your host config.
#
# Usage:
#   imports = [ "hosts/common/optional/network-storage.nix" ];
#
# The module will:
# 1. Read networkStorageInfo.${hostname} from nix-secrets
# 2. Auto-enable any services that have enable = true in the secrets
# 3. Automatically configure SOPS secrets for all SMB servers
# 4. Apply any extraConfig defined here for common, non-sensitive settings

# Reference: https://nixos.wiki/wiki/Samba
# For a user called `my_user` to be authenticated on the samba server, you must add their password using
# smbpasswd -a my_user

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

  serverConfig = hostConfig.server or { };
  clientConfig = hostConfig.client or { };
  sambaConfig = clientConfig.samba or null;

  # Extract all server names from samba configuration
  sambaServers = if sambaConfig != null then builtins.attrNames (sambaConfig.servers or { }) else [ ];
in
{
  # Auto-enable services based on nix-secrets configuration
  networkStorage = {
    # Server auto-enable
    server = {
      nfs.enable = lib.mkDefault (serverConfig.nfs.enable or false);
      samba.enable = lib.mkDefault (serverConfig.samba.enable or false);

      # Common server extraConfig (non-sensitive, applies to all hosts)
      # These are host-agnostic settings that you want to enforce globally

      # Example NFS extraConfig:
      # nfs.extraConfig = ''
      #   # Global read-only public share
      #   /export/public *(ro,sync,no_subtree_check)
      # '';

      # Example Samba extraConfig:
      # samba.extraGlobalConfig = {
      #   # Force minimum SMB protocol version for security
      #   "server min protocol" = "SMB2";
      #   "client max protocol" = "SMB3";
      #
      #   # Disable printer sharing globally
      #   "load printers" = "no";
      #   "printing" = "bsd";
      #   "printcap name" = "/dev/null";
      #   "disable spoolss" = "yes";
      # };
    };

    # Client auto-enable
    client = {
      nfs.enable = lib.mkDefault (clientConfig.nfs.enable or false);
      samba.enable = lib.mkDefault (clientConfig.samba.enable or false);

      # [WORKAROUND: systemd 258 + NFS fd store activation freeze]
      # Refs:
      #   https://github.com/NixOS/nixpkgs/issues/375376
      #   https://github.com/systemd/systemd/issues/39354
      #   https://discourse.nixos.org/t/failed-to-restart-sysinit-reactivation-target/58634/10
      #
      # systemd re-exec (and sysinit-reactivation during nixos-rebuild switch)
      # holds NFS mount fd's in its fd store; systemd 258's generator sandbox
      # fork path fails with EPROTO when those fd's exist, freezing PID 1.
      # Making NFS mounts autofs-managed ensures no live NFS fd crosses
      # activation: unused mounts auto-unmount after idle-timeout, and the
      # .automount unit only holds a local autofs fd (not an NFS socket).
      #
      # Per-host override:
      #   lib.mkForce [...] to drop this workaround entirely
      #   [ ... ] to append extras (listOf merges via concatLists)
      #
      # Remove once upstream systemd or nixpkgs ships a fix clearing
      # network-fs fd's from fd store before generator sandbox fork.
      nfs.extraOptions = [
        "x-systemd.automount"
        "noauto"
        "x-systemd.idle-timeout=60"
        "x-systemd.mount-timeout=10"
        "_netdev"
      ];

      # Common client mount options (applies to all mounts)
      # These will be added to options specified in nix-secrets

      # Example Samba mount options:
      # samba.extraOptions = [
      #   "vers=3.0"    # Force SMB version
      #   "iocharset=utf8"
      # ];
    };
  };

  # Automatically configure SOPS secrets for all SMB servers
  sops.secrets = lib.mkIf (sambaConfig.enable or false) (
    lib.listToAttrs (
      map (serverName: {
        name = "samba-${serverName}";
        value = {
          sopsFile = lib.mkDefault (inputs.nix-secrets + "/secrets/${hostname}.yaml");
          key = "samba/${serverName}";
        };
      }) sambaServers
    )
  );
}
