{
  config,
  pkgs,
  inputs,
  ...
}:
let
  # Extract attic service info from hostSpec
  hostName = config.hostSpec.hostName;
  atticInfo = config.hostSpec.serviceInfo.${hostName}.attic or { };
  servername = atticInfo.servername;
  endpoint = atticInfo.endpoint;
  homeDirectory = config.home.homeDirectory;
  # Setup sops for token management
  sopsFolder = builtins.toString inputs.nix-secrets + "/secrets";
  sopsFile = sopsFolder + "/shared.yaml";
in
{
  # Import sops secrets
  sops.secrets.attic-token = {
    sopsFile = sopsFile;
    key = "attic.token";
  };
  sops.secrets.attic-pubkey = {
    sopsFile = sopsFile;
    key = "attic.homielab-PubKey";
  };

  # environment.systemPackages = [
  #   pkgs.unstable.attic-client
  # ];
  home.packages = builtins.attrValues {
    inherit (pkgs)
      attic-client
      ;
  };

  nix.settings = {
    substituters = [
      "${endpoint}"
    ];
    trusted-public-keys = [
      "${attic-pubkey}"  # Fixed public key
    ];
  };

  # Generate attic client config
  home.file.".config/attic/config.toml".text = ''
    default-server = "${servername}"

    [servers.${servername}]
    endpoint = "${endpoint}"
    token = "${config.sops.secrets.attic-token.path}"
  '';
}