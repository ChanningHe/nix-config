{
  config,
  lib,
  pkgs,
  inputs,
  isDarwin, # Use isDarwin from specialArgs to avoid infinite recursion with config.hostSpec.isDarwin
  ...
}:
let
  hostName = config.hostSpec.hostName;
  # Per-host config takes precedence; fall back to global serviceInfo.attic
  atticInfo =
    config.hostSpec.serviceInfo.${hostName}.attic or config.hostSpec.serviceInfo.attic or { };
  servername = atticInfo.servername or "";
  endpoint = atticInfo.endpoint or "";

  # Extract hostname from endpoint (e.g., "attic.hlpj.cc/homielab" -> "attic.hlpj.cc")
  endpointHost = lib.head (lib.splitString "/" endpoint);

  # Cache name is the trailing path component of the endpoint
  cacheName = atticInfo.cache or (lib.last (lib.splitString "/" endpoint));

  userGroup = if isDarwin then "staff" else config.users.users.${config.hostSpec.username}.group;

  netrcPath = "${config.hostSpec.home}/.config/attic/netrc";
  configDir = "${config.hostSpec.home}/.config/attic";

  sopsFolder = builtins.toString inputs.nix-secrets + "/secrets";
  hasSharedYaml = builtins.pathExists "${sopsFolder}/shared.yaml";
in
{
  config = lib.mkIf (servername != "" && endpoint != "") (
    {
      sops.secrets = lib.mkIf hasSharedYaml {
        "attic/token" = {
          sopsFile = "${sopsFolder}/shared.yaml";
          mode = "0400";
          owner = config.hostSpec.username;
          group = userGroup;
        };
      };

      sops.templates."attic-config.toml" = {
        content = ''
          default-server = "${servername}"

          [servers.${servername}]
          endpoint = "https://${endpoint}"
          token = "${config.sops.placeholder."attic/token"}"
        '';
        owner = config.hostSpec.username;
        group = userGroup;
        mode = "0644";
      };

      sops.templates."attic-netrc" = {
        content = ''
          machine ${endpointHost}
          password ${config.sops.placeholder."attic/token"}
        '';
        owner = config.hostSpec.username;
        group = userGroup;
        mode = "0600";
      };

      environment.systemPackages = [ pkgs.unstable.attic-client ];

      nix.settings = {
        substituters = lib.mkBefore [ "https://${endpoint}" ];
        # Attic signs with the cache name, not the endpoint host.
        trusted-public-keys = lib.mkBefore [
          "${cacheName}:m9rTuwjBlORefVuHByPil1ymtrcqtJIQPh9AmXv93cU="
        ];
        netrc-file = netrcPath;
      };
    }
    # lib.optionalAttrs ensures the key is absent entirely on the other platform,
    # preventing "option does not exist" errors (lib.mkIf leaves the key present).
    // lib.optionalAttrs isDarwin {
      system.activationScripts.postActivation.text = ''
        mkdir -p ${configDir}
        chown ${config.hostSpec.username}:staff ${configDir}
        ln -sf ${config.sops.templates."attic-config.toml".path} ${configDir}/config.toml
        ln -sf ${config.sops.templates."attic-netrc".path} ${netrcPath}
      '';
    }
    // lib.optionalAttrs (!isDarwin) {
      # Auto-push every locally built store path to the cache
      systemd.services.attic-watch-store = {
        description = "Push new store paths to Attic cache ${cacheName}";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        # attic resolves config.toml/netrc relative to $HOME
        environment.HOME = config.hostSpec.home;
        serviceConfig = {
          ExecStart = "${pkgs.unstable.attic-client}/bin/attic watch-store ${cacheName}";
          User = config.hostSpec.username;
          Restart = "on-failure";
          RestartSec = 30;
        };
      };

      systemd.tmpfiles.rules = [
        "d ${config.hostSpec.home}/.config 0755 ${config.hostSpec.username} ${userGroup} -"
        "d ${configDir} 0755 ${config.hostSpec.username} ${userGroup} -"
        "L+ ${configDir}/config.toml - ${config.hostSpec.username} ${userGroup} - ${
          config.sops.templates."attic-config.toml".path
        }"
        "L+ ${netrcPath} - ${config.hostSpec.username} ${userGroup} - ${
          config.sops.templates."attic-netrc".path
        }"
      ];
    }
  );
}
