# Network Storage Module for NixOS (NFS & Samba Server/Client)
# This module provides a way to configure NFS and Samba servers and clients
# based on host-specific configurations from nix-secrets
{
  config,
  lib,
  inputs,
  pkgs,
  ...
}:
let
  cfg = config.networkStorage;

  # Read network storage info from nix-secrets
  networkStorageInfo = inputs.nix-secrets.networkStorageInfo or { };

  # Get configuration for current host
  hostConfig = networkStorageInfo.${cfg.hostname} or { };
  serverConfig = hostConfig.server or { };
  clientConfig = hostConfig.client or { };

  # Server configs
  nfsServerConfig = serverConfig.nfs or null;
  sambaServerConfig = serverConfig.samba or null;

  # Client configs
  nfsClientConfig = clientConfig.nfs or null;
  sambaClientConfig = clientConfig.samba or null;

  # Check if services are enabled
  nfsServerEnabled = cfg.server.nfs.enable && nfsServerConfig != null;
  sambaServerEnabled = cfg.server.samba.enable && sambaServerConfig != null;
  nfsClientEnabled = cfg.client.nfs.enable && nfsClientConfig != null;
  sambaClientEnabled = cfg.client.samba.enable && sambaClientConfig != null;

  # Get samba servers list (new structure)
  sambaServers = if sambaClientEnabled then (sambaClientConfig.servers or { }) else { };

  # Flatten all samba mounts from all servers with their credentials
  allSambaMounts =
    if sambaClientEnabled then
      lib.flatten (
        lib.mapAttrsToList (
          serverName: serverConfig:
          map (
            mount:
            mount
            // {
              # Add credentials path from sops if not explicitly specified
              credentials = mount.credentials or config.sops.secrets."samba-${serverName}".path;
            }
          ) (serverConfig.mounts or [ ])
        ) sambaServers
      )
    else
      [ ];
in
{
  options.networkStorage = {
    hostname = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      description = ''
        Hostname to lookup in networkStorageInfo.
        Defaults to the system hostname.
      '';
    };

    server = {
      nfs = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Enable NFS server with configuration from nix-secrets.
            Configuration must exist in networkStorageInfo.''${hostname}.server.nfs
          '';
        };

        extraConfig = lib.mkOption {
          type = lib.types.lines;
          default = "";
          description = ''
            Additional global NFS configuration to append to /etc/exports.
            This is for non-sensitive, host-agnostic settings.
          '';
          example = ''
            # Global NFS settings
            /export/public *(ro,sync)
          '';
        };
      };

      samba = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Enable Samba server with configuration from nix-secrets.
            Configuration must exist in networkStorageInfo.''${hostname}.server.samba
          '';
        };

        extraGlobalConfig = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.oneOf [
              lib.types.str
              lib.types.bool
              lib.types.int
              (lib.types.listOf lib.types.str)
            ]
          );
          default = { };
          description = ''
            Additional global Samba configuration to merge with settings from nix-secrets.
            This is for non-sensitive, host-agnostic settings.
            Will be merged into services.samba.settings.global.
          '';
          example = {
            "server min protocol" = "SMB2";
            "client max protocol" = "SMB3";
          };
        };
      };
    };

    client = {
      nfs = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Enable NFS client mounts from nix-secrets.
            Configuration must exist in networkStorageInfo.''${hostname}.client.nfs
          '';
        };

        extraOptions = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            Additional NFS mount options to add to all mounts.
            These will be merged with per-mount options from nix-secrets.
          '';
          example = [
            "soft"
            "timeo=30"
            "retrans=3"
          ];
        };
      };

      samba = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Enable Samba client mounts from nix-secrets.
            Configuration must exist in networkStorageInfo.''${hostname}.client.samba
          '';
        };

        extraOptions = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            Additional Samba mount options to add to all mounts.
            These will be merged with per-mount options from nix-secrets.
          '';
          example = [
            "vers=3.0"
            "sec=ntlmssp"
          ];
        };
      };
    };
  };

  config = lib.mkMerge [
    # ===== NFS Server Configuration =====
    (lib.mkIf nfsServerEnabled {
      services.nfs.server = {
        enable = true;
        # Combine exports from secrets and local extraConfig
        exports =
          lib.trim nfsServerConfig.exports
          + (lib.optionalString (
            cfg.server.nfs.extraConfig != ""
          ) "\n${lib.trim cfg.server.nfs.extraConfig}");
      };

      # Open firewall for NFS
      networking.firewall.allowedTCPPorts = [
        111 # rpcbind
        2049 # nfs
        20048 # mountd
      ];
      networking.firewall.allowedUDPPorts = [
        111 # rpcbind
        2049 # nfs
        20048 # mountd
      ];
    })

    # ===== Samba Server Configuration =====
    (lib.mkIf sambaServerEnabled (
      let
        # Merge global configs: secrets config + extraGlobalConfig
        mergedGlobal = (sambaServerConfig.global or { }) // cfg.server.samba.extraGlobalConfig;
        # Remove 'global' and 'enable' from sambaServerConfig to get only the shares
        shares = builtins.removeAttrs sambaServerConfig [
          "global"
          "enable"
        ];
        # Reconstruct settings with merged global
        settings = shares // {
          global = mergedGlobal;
        };
      in
      {
        services.samba = {
          enable = true;
          # Directly assign the merged settings (INI format)
          inherit settings;
        };

        # Enable WS-Discovery for Windows client auto-discovery
        services.samba-wsdd = {
          enable = true;
        };

        # Open firewall for Samba
        networking.firewall.allowedTCPPorts = [
          139
          445
        ]; # Samba
        networking.firewall.allowedUDPPorts = [
          137
          138
        ]; # NetBIOS
      }
    ))

    # ===== NFS Client Configuration =====
    (lib.mkIf nfsClientEnabled (
      let
        mounts = nfsClientConfig.mounts or [ ];
        # Generate fileSystems configuration for each mount
        fileSystemsConfig = builtins.listToAttrs (
          map (mount: {
            name = mount.mountPoint;
            value = {
              device = "${mount.server}:${mount.remotePath}";
              fsType = "nfs";
              options = (mount.options or [ ]) ++ cfg.client.nfs.extraOptions;
            };
          }) mounts
        );
      in
      {
        fileSystems = fileSystemsConfig;
      }
    ))

    # ===== Samba Client Configuration =====
    (lib.mkIf sambaClientEnabled (
      let
        # Generate fileSystems configuration for each mount
        fileSystemsConfig = builtins.listToAttrs (
          map (mount: {
            name = mount.mountPoint;
            value = {
              device = mount.share;
              fsType = "cifs";
              options =
                (mount.options or [ ])
                ++ cfg.client.samba.extraOptions
                ++ (lib.optionals (mount ? credentials) [ "credentials=${mount.credentials}" ]);
            };
          }) allSambaMounts
        );
      in
      {
        fileSystems = fileSystemsConfig;
        # Ensure cifs-utils is available for mounting
        environment.systemPackages = [ pkgs.cifs-utils ];
      }
    ))

    # ===== Validation: Warn if enabled but no config found =====
    (lib.mkIf (cfg.server.nfs.enable && nfsServerConfig == null) {
      warnings = [
        ''
          networkStorage.server.nfs.enable is true but no NFS server configuration found for host '${cfg.hostname}'.
          Expected configuration at: networkStorageInfo.${cfg.hostname}.server.nfs in nix-secrets.
        ''
      ];
    })

    (lib.mkIf (cfg.server.samba.enable && sambaServerConfig == null) {
      warnings = [
        ''
          networkStorage.server.samba.enable is true but no Samba server configuration found for host '${cfg.hostname}'.
          Expected configuration at: networkStorageInfo.${cfg.hostname}.server.samba in nix-secrets.
        ''
      ];
    })

    (lib.mkIf (cfg.client.nfs.enable && nfsClientConfig == null) {
      warnings = [
        ''
          networkStorage.client.nfs.enable is true but no NFS client configuration found for host '${cfg.hostname}'.
          Expected configuration at: networkStorageInfo.${cfg.hostname}.client.nfs in nix-secrets.
        ''
      ];
    })

    (lib.mkIf (cfg.client.samba.enable && sambaClientConfig == null) {
      warnings = [
        ''
          networkStorage.client.samba.enable is true but no Samba client configuration found for host '${cfg.hostname}'.
          Expected configuration at: networkStorageInfo.${cfg.hostname}.client.samba in nix-secrets.
        ''
      ];
    })
  ];
}
