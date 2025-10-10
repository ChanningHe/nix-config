# Pure NixOS module for Komodo Periphery
# This module is generic and can be contributed to nixpkgs
# No sops, no nix-secrets, no hostSpec - just pure NixOS module definition
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.komodo-periphery;

  # Generate TOML config content
  tomlConfig = ''
    ################################
    # KOMODO PERIPHERY CONFIG
    ################################

    ## Port periphery will run on
    ## Default: 8120
    port = ${toString cfg.port}

    ## Bind IP address
    ## Default: [::]
    bind_ip = "${cfg.bindIp}"

    ## Root directory for periphery data
    ## Default: $HOME/.config/komodo-periphery
    root_directory = "${cfg.rootDirectory}"

    ## Repository directory
    ## Default: ${cfg.rootDirectory}/repos
    repo_dir = "${cfg.rootDirectory}/repos"

    ## Stack directory
    ## Default: ${cfg.rootDirectory}/stacks
    stack_dir = "${cfg.rootDirectory}/stacks"

    ## SSL Configuration
    ssl_enabled = ${if cfg.ssl.enable then "true" else "false"}
    ${lib.optionalString cfg.ssl.enable ''
    ssl_key_file = "${cfg.ssl.keyFile}"
    ssl_cert_file = "${cfg.ssl.certFile}"
    ''}

    ## Logging Configuration
    [logging]
    level = "${cfg.logging.level}"
    stdio = "${cfg.logging.stdio}"
    ${lib.optionalString (cfg.logging.otlpEndpoint != "") ''
    otlp_endpoint = "${cfg.logging.otlpEndpoint}"
    ''}

    ## Security Configuration
    ## Limit IP addresses which can call the periphery API
    allowed_ips = [${lib.concatMapStringsSep ", " (ip: ''"${ip}"'') cfg.allowedIps}]

    ## Require callers to provide passkeys to access the periphery API
    passkeys = [${lib.concatMapStringsSep ", " (key: ''"${key}"'') cfg.passkeys}]

    ## Additional config sections
    ${cfg.extraConfig}
  '';
in
{
  options.services.komodo-periphery = {
    enable = lib.mkEnableOption "Komodo Periphery Agent";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.komodo;
      defaultText = lib.literalExpression "pkgs.komodo";
      description = "The komodo package to use.";
    };

    configFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to the periphery configuration file.
        If null, a configuration file will be generated from the module options.
        
        When using sops-nix for secrets, the project integration layer will
        override this with the sops template path (/run/secrets/rendered/...).
        
        You can also manually specify a custom config file path.
      '';
      example = "/etc/komodo/periphery.config.toml";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8120;
      description = "Port for the Periphery agent to listen on.";
    };

    bindIp = lib.mkOption {
      type = lib.types.str;
      default = "[::]";
      description = "IP address to bind to. Use [::] for all IPv6/IPv4.";
    };

    rootDirectory = lib.mkOption {
      type = lib.types.path;
      default =
        if cfg.user == "root"
        then "/root/.config/komodo-periphery"
        else if cfg.user == "komodo-periphery"
        then "/var/lib/komodo-periphery"
        else "/home/${cfg.user}/.config/komodo-periphery";
      defaultText = lib.literalExpression ''
        if config.services.komodo-periphery.user == "root"
        then "/root/.config/komodo-periphery"
        else if config.services.komodo-periphery.user == "komodo-periphery"
        then "/var/lib/komodo-periphery"
        else "/home/''${config.services.komodo-periphery.user}/.config/komodo-periphery"
      '';
      description = "Root directory for Komodo Periphery data (repos, stacks, ssl).";
    };

    ssl = {
      enable = lib.mkEnableOption "SSL/TLS support" // {
        default = true;
      };

      keyFile = lib.mkOption {
        type = lib.types.path;
        default = "${cfg.rootDirectory}/ssl/key.pem";
        description = "Path to SSL key file.";
      };

      certFile = lib.mkOption {
        type = lib.types.path;
        default = "${cfg.rootDirectory}/ssl/cert.pem";
        description = "Path to SSL certificate file.";
      };
    };

    logging = {
      level = lib.mkOption {
        type = lib.types.enum [
          "off"
          "error"
          "warn"
          "info"
          "debug"
          "trace"
        ];
        default = "info";
        description = "Logging verbosity level.";
      };

      stdio = lib.mkOption {
        type = lib.types.enum [
          "standard"
          "json"
          "none"
        ];
        default = "standard";
        description = "Logging format for stdout/stderr.";
      };

      otlpEndpoint = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "OpenTelemetry OTLP endpoint for traces (optional).";
        example = "http://localhost:4317";
      };
    };

    allowedIps = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Limit the IP addresses which can call the periphery API.
        Supports IPv4/IPv6 addresses and subnets.
        Empty list will not block any request by IP.
      '';
      example = [ "::ffff:12.34.56.78" "10.0.10.0/24" ];
    };

    passkeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Require callers to provide one of the provided passkeys to access the periphery API.
        Empty list will not require any passkey to be passed by core.
        
        WARNING: These will be stored in the Nix store in plain text!
        For production, consider using sops-nix to inject passkeys via secrets.
      '';
      example = [ "your-secure-passkey" ];
    };

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        Extra configuration to append to the generated config file.
        Only used if configFile is null.
      '';
      example = ''
        [secrets]
        GITHUB_TOKEN = "ghp_xxxx"
      '';
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "komodo-periphery";
      description = ''
        User to run the Periphery agent as.
        Defaults to a dedicated system user 'komodo-periphery'.
        Must have docker access and write permissions to rootDirectory.
      '';
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "komodo-periphery";
      description = "Group to run the Periphery agent as.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Create dedicated system user if using the default 'komodo-periphery' user
    users.users.${cfg.user} = lib.mkIf (cfg.user == "komodo-periphery") {
      isSystemUser = true;
      group = cfg.group;
      description = "Komodo Periphery service user";
      home = cfg.rootDirectory;
      createHome = false;
      extraGroups = [ "docker" ]; # Required for Docker access
    };

    users.groups.${cfg.group} = lib.mkIf (cfg.group == "komodo-periphery") { };

    # Ensure docker is enabled and user exists
    assertions = [
      {
        assertion = config.virtualisation.docker.enable;
        message = "Komodo Periphery requires Docker to be enabled. Set virtualisation.docker.enable = true;";
      }
      {
        assertion = 
          (cfg.user == "komodo-periphery") || 
          (cfg.user == "root") || 
          (config.users.users ? ${cfg.user});
        message = "User '${cfg.user}' must be either 'komodo-periphery' (auto-created), 'root', or an existing system user.";
      }
    ];

    # Create state directories
    systemd.tmpfiles.rules = [
      "d ${cfg.rootDirectory} 0755 ${cfg.user} ${cfg.group} -"
      "d ${cfg.rootDirectory}/repos 0755 ${cfg.user} ${cfg.group} -"
      "d ${cfg.rootDirectory}/stacks 0755 ${cfg.user} ${cfg.group} -"
      "d ${cfg.rootDirectory}/ssl 0700 ${cfg.user} ${cfg.group} -"
    ];

    # Generate config file in /etc if configFile is not provided
    environment.etc."komodo-periphery/config.toml" = lib.mkIf (cfg.configFile == null) {
      text = tomlConfig;
      mode = "0400";
      user = cfg.user;
      group = cfg.group;
    };

    # Define the systemd service
    systemd.services.komodo-periphery = {
      description = "Komodo Periphery Agent - Connect with Komodo Core";
      after = [
        "network.target"
        "docker.service"
      ];
      wants = [ "docker.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        Restart = "on-failure";
        RestartSec = "10s";
        TimeoutStartSec = 0;

        # Set HOME for the service
        Environment = "HOME=${
          if cfg.user == "root" then "/root" else config.users.users.${cfg.user}.home
        }";

        # Use the config file (use /etc if configFile not specified)
        # Note: komodo package provides 'periphery' binary, not 'komodo'
        ExecStart = "${cfg.package}/bin/periphery --config-path ${
          if cfg.configFile != null then cfg.configFile else "/etc/komodo-periphery/config.toml"
        }";

        # Security hardening (optional, adjust as needed)
        # ProtectSystem = "strict";
        # ReadWritePaths = [ cfg.rootDirectory ];
        # PrivateTmp = true;
        # NoNewPrivileges = true;
      };
    };

    # Open firewall port if needed
    # Note: Commented out by default - users should explicitly enable this
    # networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
