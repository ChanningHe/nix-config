# Project-specific integration for Komodo Periphery
# This file handles:
# - Import of the pure NixOS module
# - sops-nix integration for secrets
# - hostSpec.serviceInfo configuration reading
# - Docker auto-enablement
# - Any other nix-config specific logic
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.services.komodo-periphery;
  hostName = config.hostSpec.hostName;
  hostKomodo = config.hostSpec.serviceInfo.${hostName}.komodo or { };
  sopsFolder = builtins.toString inputs.nix-secrets + "/secrets";
  sopsFile = "${sopsFolder}/${hostName}.yaml";
  # Use lib.pathExists instead of builtins.pathExists to avoid evaluation issues
  hasSopsFile = lib.pathExists sopsFile;

  # Detect which komodo secrets exist in the sops file
  # YAML key names are plaintext, so we can check for their presence
  sopsContent = if hasSopsFile then builtins.readFile sopsFile else "";
  # Match each part of the key path separately (YAML uses nested indentation, not "a/b:" format)
  hasSecretKey =
    key:
    let
      parts = lib.splitString "/" key;
    in
    lib.all (part: builtins.match ".*${part}:.*" sopsContent != null) parts;

  # Check for different authentication methods
  hasPasskeys = hasSecretKey "komodo/passkeys";
  hasPrivateKey = hasSecretKey "komodo/private_key";
  hasCorePublicKeys = hasSecretKey "komodo/core_public_keys";
  hasOnboardingKey = hasSecretKey "komodo/onboarding_key";

  # SOPS age key for decrypting secrets in git repos
  hasSopsAgeKey = hasSecretKey "komodo/sops_age_key";

  # SSL certificates
  hasSslKey = hasSecretKey "komodo/ssl_key";
  hasSslCert = hasSecretKey "komodo/ssl_cert";
in
{
  # Import the pure NixOS module
  imports = [
    (lib.custom.relativeToRoot "modules/hosts/nixos/komodo")
  ];

  config = lib.mkMerge [
    # Import settings from hostSpec.serviceInfo if komodo config exists
    # Direct mapping - use v2 format in hostSpec.serviceInfo
    (lib.mkIf (hostKomodo != { }) {
      services.komodo-periphery = {
        # Force package to unstable version
        package = lib.mkDefault pkgs.unstable.komodo;
      }
      # Map all other fields from hostKomodo with mkDefault
      // (builtins.mapAttrs (_: lib.mkDefault) (builtins.removeAttrs hostKomodo [ "package" ]));
    })

    # sops-nix integration (only if service is enabled and sops file exists)
    (lib.mkIf (cfg.enable && hasSopsFile) {
      # Define sops secrets - only for keys that exist in the sops file
      sops.secrets =
        # SSL certificates - only if SSL is enabled and keys exist
        lib.optionalAttrs (cfg.inbound.ssl.enable && hasSslKey) {
          "komodo/ssl_key" = {
            sopsFile = sopsFile;
            owner = cfg.user;
            group = cfg.group;
            mode = "0400";
            path = "${cfg.rootDirectory}/ssl/key.pem";
          };
        }
        // lib.optionalAttrs (cfg.inbound.ssl.enable && hasSslCert) {
          "komodo/ssl_cert" = {
            sopsFile = sopsFile;
            owner = cfg.user;
            group = cfg.group;
            mode = "0400";
            path = "${cfg.rootDirectory}/ssl/cert.pem";
          };
        }
        # v1 authentication - Passkeys (legacy)
        // lib.optionalAttrs hasPasskeys {
          "komodo/passkeys" = {
            sopsFile = sopsFile;
            owner = cfg.user;
            group = cfg.group;
            mode = "0400";
          };
        }
        # v2 authentication - Private key
        // lib.optionalAttrs hasPrivateKey {
          "komodo/private_key" = {
            sopsFile = sopsFile;
            owner = cfg.user;
            group = cfg.group;
            mode = "0400";
          };
        }
        # v2 authentication - Core public keys
        // lib.optionalAttrs hasCorePublicKeys {
          "komodo/core_public_keys" = {
            sopsFile = sopsFile;
            owner = cfg.user;
            group = cfg.group;
            mode = "0400";
          };
        }
        # v2 outbound - Onboarding key
        // lib.optionalAttrs hasOnboardingKey {
          "komodo/onboarding_key" = {
            sopsFile = sopsFile;
            owner = cfg.user;
            group = cfg.group;
            mode = "0400";
          };
        }
        # SOPS age key for decrypting secrets in git repos
        // lib.optionalAttrs hasSopsAgeKey {
          "komodo/sops_age_key" = {
            sopsFile = sopsFile;
            owner = cfg.user;
            group = cfg.group;
            mode = "0400";
          };
        };

      # Configure Komodo Periphery to use sops secrets
      services.komodo-periphery = lib.mkMerge [
        # SSL configuration (v2: inbound.ssl)
        (lib.mkIf (cfg.inbound.ssl.enable && hasSslKey && hasSslCert) {
          inbound.ssl = {
            keyFile = lib.mkForce config.sops.secrets."komodo/ssl_key".path;
            certFile = lib.mkForce config.sops.secrets."komodo/ssl_cert".path;
          };
        })

        # v1 authentication - Passkeys
        (lib.mkIf hasPasskeys {
          passkeyFiles = config.sops.secrets."komodo/passkeys".path;
        })

        # v2 authentication - Private key
        (lib.mkIf hasPrivateKey {
          auth.privateKey = "file:${config.sops.secrets."komodo/private_key".path}";
        })

        # v2 authentication - Core public keys
        (lib.mkIf hasCorePublicKeys {
          auth.corePublicKeys = [ "file:${config.sops.secrets."komodo/core_public_keys".path}" ];
        })

        # v2 outbound - Onboarding key
        (lib.mkIf hasOnboardingKey {
          outbound.onboardingKeyFile = config.sops.secrets."komodo/onboarding_key".path;
        })

        # SOPS age key for decrypting secrets in git repos
        (lib.mkIf hasSopsAgeKey {
          environment = lib.mkDefault {
            SOPS_AGE_KEY_FILE = config.sops.secrets."komodo/sops_age_key".path;
          };
        })
      ];
      # Optional: If using GitHub token, add it here
      # services.komodo-periphery.environment = {
      #   GITHUB_TOKEN = config.sops.secrets."komodo/github_token".path;
      # };
    })

    # Additional configuration when service is enabled
    (lib.mkIf cfg.enable {
      # Ensure user is in docker group (the module already handles this for default user)
      users.users.${cfg.user} = lib.mkIf (cfg.user != "root" && cfg.user != "komodo-periphery") {
        extraGroups = [ "docker" ];
      };

      # Enable Docker (the module already handles this by default)
      virtualisation.docker = {
        enable = lib.mkDefault true;
        autoPrune = {
          enable = lib.mkDefault true;
          dates = lib.mkDefault "weekly";
        };
      };

      # Wait for sops-nix service if using any sops secrets
      systemd.services.komodo-periphery = {
        after = lib.mkIf hasSopsFile [ "sops-nix.service" ];
        wants = lib.mkIf hasSopsFile [ "sops-nix.service" ];

        # Add required tools to PATH
        path = with pkgs; [
          git
          age
          sops
          docker
          bash
          openssh
        ];
      };

      # Optionally open firewall port
      # Uncomment if you need external access to Periphery
      # networking.firewall.allowedTCPPorts = [ cfg.port ];
    })
  ];
}
