# Project-specific integration for Komodo Periphery
# This file handles:
# - sops-nix integration
# - networkInfo configuration reading
# - Docker auto-enablement
# - Any other nix-config specific logic
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
with lib;
let
  cfg = config.services.komodo-periphery;
  hostName = config.hostSpec.hostName;
  hostKomodo = config.hostSpec.serviceInfo.${hostName}.komodo or { };
  sopsFolder = builtins.toString inputs.nix-secrets + "/secrets";

  # TOML format for sops template generation
  settingsFormat = pkgs.formats.toml { };

  # Generate structured config with sops placeholders
  genSopsSettings = 
    let 
      baseSettings = {
        # Core settings
        port = cfg.port;
        bind_ip = cfg.bindIp;
        root_directory = cfg.rootDirectory;
        repo_dir = "${cfg.rootDirectory}/repos";
        stack_dir = "${cfg.rootDirectory}/stacks";
        
        # SSL configuration (use sops-managed paths)
        ssl_enabled = cfg.ssl.enable;
      } // optionalAttrs cfg.ssl.enable {
        ssl_key_file = "${cfg.rootDirectory}/ssl/key.pem";
        ssl_cert_file = "${cfg.rootDirectory}/ssl/cert.pem";
      } // {
        # Logging configuration
        logging = {
          level = cfg.logging.level;
          stdio = cfg.logging.stdio;
        } // optionalAttrs (cfg.logging.otlpEndpoint != "") {
          otlp_endpoint = cfg.logging.otlpEndpoint;
        };
        
        # Security settings with sops integration
        allowed_ips = cfg.allowedIps;
        
        # Feature toggles
        disable_terminals = cfg.disableTerminals;
        disable_container_exec = cfg.disableContainerExec;
        
        # Polling settings  
        stats_polling_rate = cfg.statsPollingRate;
        container_stats_polling_rate = cfg.containerStatsPollingRate;
        
        # Docker settings
        legacy_compose_cli = cfg.legacyComposeCli;
        
        # Disk monitoring
        include_disk_mounts = cfg.includeDiskMounts;
        exclude_disk_mounts = cfg.excludeDiskMounts;
      } // optionalAttrs (config.sops.secrets ? "komodo/passkeys") {
        # Use sops placeholder for passkeys if secret exists
        passkeys = [ config.sops.placeholder."komodo/passkeys" ];
      } // optionalAttrs (!(config.sops.secrets ? "komodo/passkeys") && cfg.passkeys != []) {
        # Fall back to plain passkeys if no sops secret
        passkeys = cfg.passkeys;
      } // optionalAttrs (config.sops.secrets ? "komodo/github_token") {
        # Optional GitHub token from sops
        secrets.GITHUB_TOKEN = config.sops.placeholder."komodo/github_token";
      } // cfg.extraSettings;
    in
    # Filter out null values and empty objects/lists
    filterAttrsRecursive (_: v: v != null && v != {} && v != []) baseSettings;

  # Legacy support: generate TOML config with sops placeholders as text
  tomlConfigWithSops = 
    settingsFormat.generate "komodo-periphery-sops.toml" genSopsSettings;
in
{
  # Import the pure NixOS module
  imports = [
    (lib.custom.relativeToRoot "modules/hosts/nixos/komodo")
  ];

  # Configure from networkInfo if available
  config = lib.mkMerge [
    # Import settings from hostSpec.networkInfo if komodo config exists
    (lib.mkIf (hostKomodo != { }) {
      services.komodo-periphery = {
        enable = lib.mkDefault (hostKomodo.enable or false);
        package = lib.mkDefault pkgs.unstable.komodo;
        port = lib.mkDefault (hostKomodo.port or 8120);
        # Only override user/group if explicitly set in hostKomodo config
        user = lib.mkIf (hostKomodo ? user) (lib.mkDefault hostKomodo.user);
        group = lib.mkIf (hostKomodo ? group) (lib.mkDefault hostKomodo.group);
        # rootDirectory uses module defaults which adapts to the user
        rootDirectory = lib.mkIf (hostKomodo ? rootDirectory) (lib.mkDefault hostKomodo.rootDirectory);
        ssl.enable = lib.mkDefault (hostKomodo.sslEnabled or true);
        logging.level = lib.mkDefault (hostKomodo.logLevel or "info");
        # Security options
        allowedIps = lib.mkDefault (hostKomodo.allowedIps or [ ]);
        passkeys = lib.mkDefault (hostKomodo.passkeys or [ ]);
        # Advanced options
        disableTerminals = lib.mkDefault (hostKomodo.disableTerminals or false);
        disableContainerExec = lib.mkDefault (hostKomodo.disableContainerExec or false);
        statsPollingRate = lib.mkDefault (hostKomodo.statsPollingRate or "5-sec");
        containerStatsPollingRate = lib.mkDefault (hostKomodo.containerStatsPollingRate or "30-sec");
        legacyComposeCli = lib.mkDefault (hostKomodo.legacyComposeCli or false);
        includeDiskMounts = lib.mkDefault (hostKomodo.includeDiskMounts or [ ]);
        excludeDiskMounts = lib.mkDefault (hostKomodo.excludeDiskMounts or [ ]);
        # systemd environment variables
        systemdEnvironment = lib.mkDefault (hostKomodo.systemdEnvironment or []);
      };
    })

    # sops-nix integration (only if service is enabled and passkeys secret exists)
    (lib.mkIf (cfg.enable && builtins.pathExists "${sopsFolder}/${hostName}.yaml") {
      # Create sops template for config if we have passkeys secret
      sops.templates."komodo-periphery-config.toml" = lib.mkIf (config.sops.secrets ? "komodo/passkeys") {
        owner = cfg.user;
        group = cfg.group;
        mode = "0400";
        content = builtins.readFile tomlConfigWithSops + optionalString (cfg.extraConfig != "") ("\n" + cfg.extraConfig);
      };

      # Use the sops template path if passkeys secret exists, otherwise let module generate config
      services.komodo-periphery.configFile = lib.mkIf (config.sops.secrets ? "komodo/passkeys")
        config.sops.templates."komodo-periphery-config.toml".path;
    })

    # Additional configuration when service is enabled
    (lib.mkIf cfg.enable {
      # Ensure user is in docker group if using an existing user (not komodo-periphery or root)
      users.users.${cfg.user} = lib.mkIf (cfg.user != "root" && cfg.user != "komodo-periphery") {
        extraGroups = [ "docker" ];
      };

      # The pure module will generate config at /etc/komodo-periphery/config.toml

      # Define sops secrets for SSL, passkeys and optional tokens
      sops.secrets = lib.mkMerge [
        # SSL certificates
        (lib.mkIf (cfg.ssl.enable && builtins.pathExists "${sopsFolder}/${hostName}.yaml") {
          "komodo/ssl_key" = {
            sopsFile = "${sopsFolder}/${hostName}.yaml";
            owner = cfg.user;
            group = cfg.group;
            mode = "0400";
            path = "${cfg.rootDirectory}/ssl/key.pem";
          };
          "komodo/ssl_cert" = {
            sopsFile = "${sopsFolder}/${hostName}.yaml";
            owner = cfg.user;
            group = cfg.group;
            mode = "0400";
            path = "${cfg.rootDirectory}/ssl/cert.pem";
          };
        })

        # Passkeys (for API authentication)
        (lib.mkIf (builtins.pathExists "${sopsFolder}/${hostName}.yaml") {
          "komodo/passkeys" = {
            sopsFile = "${sopsFolder}/${hostName}.yaml";
            owner = cfg.user;
            group = cfg.group;
            mode = "0400";
            # This secret will be used in the config template
          };
        })

        # Optional: GitHub token (set first condition to true if you have this secret)
        (lib.mkIf (false && builtins.pathExists "${sopsFolder}/${hostName}.yaml") {
          "komodo/github_token" = {
            sopsFile = "${sopsFolder}/${hostName}.yaml";
            owner = cfg.user;
            group = cfg.group;
            mode = "0400";
          };
        })
      ];

      # Enable Docker (required for Komodo Periphery)
      virtualisation.docker = {
        enable = lib.mkDefault true;
        autoPrune = {
          enable = lib.mkDefault true;
          dates = lib.mkDefault "weekly";
        };
      };

      # Wait for sops-nix service if using sops template
      systemd.services.komodo-periphery.after = lib.mkIf (
        cfg.configFile == null && cfg.ssl.enable
      ) [ "sops-nix.service" ];

      # Optionally open firewall port
      # Uncomment if you need external access to Periphery
      # networking.firewall.allowedTCPPorts = [ cfg.port ];
    })
  ];
}
