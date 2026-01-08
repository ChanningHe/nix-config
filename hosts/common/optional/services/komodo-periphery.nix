# Project-specific integration for Komodo Periphery
# This file handles:
# - Import of the pure NixOS module
# - sops-nix integration for secrets
# - hostSpec.serviceInfo configuration reading
# - Docker auto-enablement
# - Any other nix-config specific logic
#
# NOTE: Currently using v1-style options for compatibility testing.
# Migration to v2 options (inbound/outbound) can be done later.
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
    (lib.mkIf (hostKomodo != { }) {
      services.komodo-periphery = {
        enable = lib.mkDefault (hostKomodo.enable or false);
        package = lib.mkDefault pkgs.unstable.komodo;

        # v1-style network options (for compatibility testing)
        port = lib.mkDefault (hostKomodo.port or 8120);
        bindIp = lib.mkDefault (hostKomodo.bindIp or "[::]");
        allowedIps = lib.mkDefault (hostKomodo.allowedIps or [ ]);

        # SSL configuration (v1 style)
        ssl.enable = lib.mkDefault (hostKomodo.sslEnabled or true);
        # SSL paths will be overridden by sops if secrets exist

        # User/Group configuration
        user = lib.mkIf (hostKomodo ? user) (lib.mkDefault hostKomodo.user);
        group = lib.mkIf (hostKomodo ? group) (lib.mkDefault hostKomodo.group);
        rootDirectory = lib.mkIf (hostKomodo ? rootDirectory) (lib.mkDefault hostKomodo.rootDirectory);

        # Logging configuration
        logging.level = lib.mkDefault (hostKomodo.logLevel or "info");
        logging.stdio = lib.mkDefault (hostKomodo.logStdio or "standard");
        logging.otlpEndpoint = lib.mkDefault (hostKomodo.otlpEndpoint or "");

        # Security options (v1 style for compatibility)
        # Note: passkeys should not be set here as they're always passed via environment variables
        # Use passkeyFiles (set below in sops integration) for file-based secrets

        # Terminal options
        disableTerminals = lib.mkDefault (hostKomodo.disableTerminals or false);
        disableContainerExec = lib.mkDefault (hostKomodo.disableContainerExec or false);

        # Stats polling
        statsPollingRate = lib.mkDefault (hostKomodo.statsPollingRate or "5-sec");
        containerStatsPollingRate = lib.mkDefault (hostKomodo.containerStatsPollingRate or "30-sec");

        # Docker options
        legacyComposeCli = lib.mkDefault (hostKomodo.legacyComposeCli or false);

        # Disk mount options
        includeDiskMounts = lib.mkDefault (hostKomodo.includeDiskMounts or [ ]);
        excludeDiskMounts = lib.mkDefault (hostKomodo.excludeDiskMounts or [ ]);

        # Environment variables
        environment = lib.mkDefault (hostKomodo.environment or { });
        environmentFile = lib.mkIf (hostKomodo ? environmentFile) (
          lib.mkDefault hostKomodo.environmentFile
        );

        # Extra settings (if specified in hostKomodo)
        extraSettings = lib.mkIf (hostKomodo ? extraSettings) (lib.mkDefault hostKomodo.extraSettings);
      };
    })

    # sops-nix integration (only if service is enabled and sops file exists)
    (lib.mkIf (cfg.enable && hasSopsFile) {
      # Define sops secrets
      sops.secrets = {
        # SSL certificates - only if SSL is enabled
        "komodo/ssl_key" = lib.mkIf cfg.ssl.enable {
          sopsFile = sopsFile;
          owner = cfg.user;
          group = cfg.group;
          mode = "0400";
          path = "${cfg.rootDirectory}/ssl/key.pem";
        };
        "komodo/ssl_cert" = lib.mkIf cfg.ssl.enable {
          sopsFile = sopsFile;
          owner = cfg.user;
          group = cfg.group;
          mode = "0400";
          path = "${cfg.rootDirectory}/ssl/cert.pem";
        };

        # Passkeys (for v1 authentication)
        # Komodo Periphery will read this file directly via PERIPHERY_PASSKEYS_FILE
        "komodo/passkeys" = {
          sopsFile = sopsFile;
          owner = cfg.user;
          group = cfg.group;
          mode = "0400";
        };

        # Optional: GitHub token (uncomment if you have this secret)
        # "komodo/github_token" = {
        #   sopsFile = sopsFile;
        #   owner = cfg.user;
        #   group = cfg.group;
        #   mode = "0400";
        # };
      };

      # Override SSL paths to use sops secret paths (only when SSL enabled)
      services.komodo-periphery.ssl = lib.mkIf cfg.ssl.enable {
        keyFile = lib.mkForce config.sops.secrets."komodo/ssl_key".path;
        certFile = lib.mkForce config.sops.secrets."komodo/ssl_cert".path;
      };

      # Use passkeyFiles to let Komodo Periphery read the secret file directly
      # The module will set PERIPHERY_PASSKEYS_FILE environment variable
      # pointing to this file, and Komodo will read it at startup
      services.komodo-periphery.passkeyFiles = config.sops.secrets."komodo/passkeys".path;

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
