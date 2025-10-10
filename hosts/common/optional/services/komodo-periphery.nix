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
let
  cfg = config.services.komodo-periphery;
  hostName = config.hostSpec.hostName;
  hostKomodo = config.hostSpec.serviceInfo.${hostName}.komodo or { };
  sopsFolder = builtins.toString inputs.nix-secrets + "/secrets";

  # Generate TOML config with sops placeholders
  tomlConfigWithSops = ''
    ################################
    # KOMODO PERIPHERY CONFIG
    ################################

    ## Port periphery will run on
    port = ${toString cfg.port}

    ## Bind IP address
    bind_ip = "${cfg.bindIp}"

    ## Root directory for periphery data
    ## Default: $HOME/.config/komodo-periphery
    root_directory = "${cfg.rootDirectory}"

    ## Repository directory
    repo_dir = "${cfg.rootDirectory}/repos"

    ## Stack directory
    stack_dir = "${cfg.rootDirectory}/stacks"

    ## SSL Configuration
    ssl_enabled = ${if cfg.ssl.enable then "true" else "false"}
    ${lib.optionalString cfg.ssl.enable ''
    ssl_key_file = "${cfg.rootDirectory}/ssl/key.pem"
    ssl_cert_file = "${cfg.rootDirectory}/ssl/cert.pem"
    ''}

    ## Logging Configuration
    [logging]
    level = "${cfg.logging.level}"
    stdio = "${cfg.logging.stdio}"
    ${lib.optionalString (cfg.logging.otlpEndpoint != "") ''
    otlp_endpoint = "${cfg.logging.otlpEndpoint}"
    ''}

    ## Security Configuration
    allowed_ips = [${lib.concatMapStringsSep ", " (ip: ''"${ip}"'') cfg.allowedIps}]
    
    ## Passkeys (from sops secrets)
    ${lib.optionalString (config.sops.secrets ? "komodo/passkeys") ''
    passkeys = ["${config.sops.placeholder."komodo/passkeys"}"]
    ''}
    ${lib.optionalString (!(config.sops.secrets ? "komodo/passkeys") && cfg.passkeys != []) ''
    passkeys = [${lib.concatMapStringsSep ", " (key: ''"${key}"'') cfg.passkeys}]
    ''}

    ## Secrets (injected via sops)
    ${lib.optionalString (config.sops.secrets ? "komodo/github_token") ''
    [secrets]
    GITHUB_TOKEN = "${config.sops.placeholder."komodo/github_token"}"
    ''}

    ## Extra configuration
    ${cfg.extraConfig}
  '';
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
      };
    })

    # sops-nix integration (only if service is enabled and passkeys secret exists)
    (lib.mkIf (cfg.enable && builtins.pathExists "${sopsFolder}/${hostName}.yaml") {
      # Create sops template for config if we have passkeys secret
      # NOTE: sops template path doesn't have .toml extension, but Komodo requires it
      # We'll use a symlink workaround
      sops.templates."komodo-periphery-config.toml" = lib.mkIf (config.sops.secrets ? "komodo/passkeys") {
        owner = cfg.user;
        group = cfg.group;
        mode = "0400";
        content = tomlConfigWithSops;
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
