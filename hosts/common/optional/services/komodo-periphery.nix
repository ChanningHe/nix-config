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
      # Define sops secrets
      sops.secrets = {
        # SSL certificates - only if SSL is enabled (v2: inbound.ssl.enable)
        "komodo/ssl_key" = lib.mkIf cfg.inbound.ssl.enable {
          sopsFile = sopsFile;
          owner = cfg.user;
          group = cfg.group;
          mode = "0400";
          path = "${cfg.rootDirectory}/ssl/key.pem";
        };
        "komodo/ssl_cert" = lib.mkIf cfg.inbound.ssl.enable {
          sopsFile = sopsFile;
          owner = cfg.user;
          group = cfg.group;
          mode = "0400";
          path = "${cfg.rootDirectory}/ssl/cert.pem";
        };

        # Passkeys (for v1 authentication - legacy)
        # Komodo Periphery will read this file directly via PERIPHERY_PASSKEYS_FILE
        "komodo/passkeys" = {
          sopsFile = sopsFile;
          owner = cfg.user;
          group = cfg.group;
          mode = "0400";
        };

        # Optional: v2 authentication keys
        # Private key (uncomment if managing via sops)
        # "komodo/private_key" = {
        #   sopsFile = sopsFile;
        #   owner = cfg.user;
        #   group = cfg.group;
        #   mode = "0400";
        # };

        # Core public keys (uncomment if managing via sops)
        "komodo/core_public_keys" = {
          sopsFile = sopsFile;
          owner = cfg.user;
          group = cfg.group;
          mode = "0400";
        };

        # Onboarding key (uncomment if using outbound mode)
        # "komodo/onboarding_key" = {
        #   sopsFile = sopsFile;
        #   owner = cfg.user;
        #   group = cfg.group;
        #   mode = "0400";
        # };

        # Optional: GitHub token (uncomment if you have this secret)
        # "komodo/github_token" = {
        #   sopsFile = sopsFile;
        #   owner = cfg.user;
        #   group = cfg.group;
        #   mode = "0400";
        # };
      };

      # Override SSL paths to use sops secret paths (v2: inbound.ssl)
      services.komodo-periphery.inbound.ssl = lib.mkIf cfg.inbound.ssl.enable {
        keyFile = lib.mkForce config.sops.secrets."komodo/ssl_key".path;
        certFile = lib.mkForce config.sops.secrets."komodo/ssl_cert".path;
      };

      # Use passkeyFiles to let Komodo Periphery read the secret file directly
      # The module will set PERIPHERY_PASSKEYS_FILE environment variable
      # pointing to this file, and Komodo will read it at startup
      services.komodo-periphery = {
        passkeyFiles = config.sops.secrets."komodo/passkeys".path;
        auth.corePublicKeys = [ config.sops.secrets."komodo/core_public_keys".path ];
      };
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
