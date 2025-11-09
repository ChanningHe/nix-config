{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  # Extract attic service info from hostSpec
  # Expected configuration in hostSpec:
  # serviceInfo.${hostName}.attic = {
  #   servername = "your-server-name";
  #   endpoint = "https://your.attic.server/cache";  
  #   publicKey = "your-attic-public-key";  # Optional, for nix cache verification
  # };
  hostName = config.hostSpec.hostName;
  atticInfo = config.hostSpec.serviceInfo.${hostName}.attic or { };
  servername = atticInfo.servername or "";
  endpoint = atticInfo.endpoint or "";
in
{
  config = lib.mkIf (atticInfo != { } && servername != "" && endpoint != "") {
  # No need to define sops secrets here - they're handled in hosts/common/core/sops.nix

  environment.systemPackages = [
    pkgs.unstable.attic-client
  ];

  nix.settings = {
    substituters = [
      "https://${endpoint}"
      "https://cache.nixos.org/"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="  # NixOS cache
      "${endpoint}:m9rTuwjBlORefVuHByPil1ymtrcqtJIQPh9AmXv93cU="
    ];
    trusted-users = [ "root" "channinghe" ];
  };

  # Use sops templates to generate attic config with secrets (only if secret is available)
  sops.templates = lib.mkIf (config.sops.secrets ? "attic/token") {
    "attic-config.toml" = {
      content = ''
        default-server = "${servername}"

        [servers.${servername}]
        endpoint = "https://${endpoint}"
        token = "${config.sops.placeholder."attic/token"}"
      '';
      owner = config.hostSpec.username;
      group = config.users.users.${config.hostSpec.username}.group;
      mode = "0644";
    };
  };

  # Create directory structure and link the generated config
  systemd.tmpfiles.rules = lib.mkIf (config.sops.secrets ? "attic/token") [
    "d ${config.hostSpec.home}/.config 0755 ${config.hostSpec.username} ${config.users.users.${config.hostSpec.username}.group} -"
    "d ${config.hostSpec.home}/.config/attic 0755 ${config.hostSpec.username} ${config.users.users.${config.hostSpec.username}.group} -"
    "L+ ${config.hostSpec.home}/.config/attic/config.toml - ${config.hostSpec.username} ${config.users.users.${config.hostSpec.username}.group} - ${config.sops.templates."attic-config.toml".path}"
  ];
  };
}