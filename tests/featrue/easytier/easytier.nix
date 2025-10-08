{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  hostName = config.hostSpec.hostName;
  hostEasytier = config.hostSpec.networkInfo.hosts.${hostName}.easytier or { };
  sopsFolder = builtins.toString inputs.nix-secrets + "/secrets";
in
{
  # Import the official easytier module from nixpkgs-unstable
  # since it's not available in nixos-25.05
  imports = [
    "${inputs.nixpkgs-unstable}/nixos/modules/services/networking/easytier.nix"
  ];

  # Only generate configuration if host has easytier defined in networkInfo
  config = lib.mkIf (hostEasytier != { }) {
    # Enable easytier service (uses official NixOS module from unstable)
    services.easytier = {
      enable = true;

      # Use unstable channel for easytier to get the latest version
      package = pkgs.unstable.easytier;

      # Generate instances from hostSpec configuration
      instances = lib.mapAttrs (instanceName: instanceConfig: {
        enable = true;

        # Use environment file for sensitive data (network_name, network_secret, peers)
        environmentFiles = [ config.sops.templates."easytier-${instanceName}-env".path ];

        # Basic settings from network.nix
        settings = {
          inherit (instanceConfig) ipv4;
          instance_name = instanceName;

          # Peers: read from sops secret as comma-separated string, then split
          # This is done at activation time via systemd service wrapper
          # For now, we'll use a custom configFile approach
          peers = instanceConfig.extraPeers or [ ];

          # Listeners
          listeners =
            instanceConfig.listeners or [
              "tcp://0.0.0.0:11010"
              "udp://0.0.0.0:11010"
            ];
        };

        # Use custom config file to inject peers from sops
        configFile = config.sops.templates."easytier-${instanceName}-config".path;

        # Extra settings (e.g., dev_name, encryption flags, etc.)
        # Merge flags from network.nix with auto-generated dev_name
        extraSettings =
          let
            # Get flags from network.nix (if any)
            networkFlags = (instanceConfig.extraSettings or { }).flags or { };
            # Set default dev_name if not specified
            defaultFlags = {
              dev_name = "tun-${instanceName}";
            };
            # Merge: network.nix flags override defaults
            mergedFlags = defaultFlags // networkFlags;
          in
          {
            flags = mergedFlags;
          }
          // (builtins.removeAttrs (instanceConfig.extraSettings or { }) [ "flags" ]);
      }) hostEasytier;
    };

    # Create sops secrets for each instance
    sops.secrets = lib.mkMerge (
      lib.mapAttrsToList (instanceName: _: {
        "easytier/${instanceName}/network_name" = {
          sopsFile = "${sopsFolder}/shared.yaml";
        };
        "easytier/${instanceName}/network_secret" = {
          sopsFile = "${sopsFolder}/shared.yaml";
        };
        "easytier/${instanceName}/peers_toml" = {
          sopsFile = "${sopsFolder}/shared.yaml";
        };
      }) hostEasytier
    );

    # Create sops templates to generate TOML config files with decrypted values
    sops.templates = lib.mkMerge (
      lib.mapAttrsToList (
        instanceName: instanceConfig:
        let
          # Get flags from network.nix
          networkFlags = (instanceConfig.extraSettings or { }).flags or { };
          defaultFlags = {
            dev_name = "tun-${instanceName}";
          };
          mergedFlags = defaultFlags // networkFlags;

          # Convert flags attrset to TOML format
          flagsToml = lib.concatStringsSep "\n" (
            lib.mapAttrsToList (
              k: v:
              if builtins.isBool v then
                "${k} = ${if v then "true" else "false"}"
              else if builtins.isInt v then
                "${k} = ${toString v}"
              else
                "${k} = \"${toString v}\""
            ) mergedFlags
          );

          # Get extraPeers from network.nix and convert to TOML
          extraPeers = instanceConfig.extraPeers or [ ];
          extraPeersToml = lib.concatMapStringsSep "\n" (peer: "[[peer]]\nuri = \"${peer}\"") extraPeers;

          # Get listeners from network.nix
          listeners =
            instanceConfig.listeners or [
              "tcp://0.0.0.0:11010"
              "udp://0.0.0.0:11010"
            ];
          listenersToml = lib.concatMapStringsSep ", " (l: "\"${l}\"") listeners;
        in
        {
          # Generate TOML config file with decrypted values
          "easytier-${instanceName}-config" = {
            owner = "root";
            mode = "0400";
            content = ''
              # EasyTier configuration for instance: ${instanceName}
              instance_name = "${instanceName}"
              ipv4 = "${instanceConfig.ipv4}"
              dhcp = false
              listeners = [${listenersToml}]

              # Network identity from sops secrets
              [network_identity]
              network_name = "${config.sops.placeholder."easytier/${instanceName}/network_name"}"
              network_secret = "${config.sops.placeholder."easytier/${instanceName}/network_secret"}"

              # Peers from sops secrets (shared.yaml)
              # Must be stored in TOML format in shared.yaml (peers_toml field)
              # Example in shared.yaml:
              #   peers_toml: |
              #     [[peer]]
              #     uri = "tcp://example.com:11010"
              #
              #     [[peer]]
              #     uri = "udp://example.com:11010"
              ${config.sops.placeholder."easytier/${instanceName}/peers_toml"}

              # Extra peers from network.nix (host-specific, unencrypted)
              ${extraPeersToml}

              # Flags (device name, encryption, etc.)
              [flags]
              ${flagsToml}
            '';
          };

          # Also create environment file (though it may not be needed anymore)
          "easytier-${instanceName}-env" = {
            content = ''
              # Environment file (kept for compatibility)
            '';
          };
        }
      ) hostEasytier
    );
  };
}
