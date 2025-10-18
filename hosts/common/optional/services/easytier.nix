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
  #sopsFolder = builtins.toString inputs.nix-secrets + "/secrets";
in
{
  imports = [
    "${inputs.nixpkgs-unstable}/nixos/modules/services/networking/easytier.nix"
  ];

  config = lib.mkIf (hostEasytier != { }) {
    services.easytier = {
      enable = true;
      package = pkgs.unstable.easytier;

      # All other configuration is in the user's TOML file at:
      # ${config.hostSpec.home}/.config/easytier/${instanceName}.toml
      instances = lib.mapAttrs (instanceName: instanceConfig: {
        enable = true;

        # Use config file from user's home directory
        # Default: $HOME/.config/easytier/${instanceName}.toml
        # User can override by setting configFile in network.nix easytier definition
        configFile =
          instanceConfig.configFile or "${config.hostSpec.home}/.config/easytier/${instanceName}.toml";
      }) hostEasytier;
    };

    systemd.tmpfiles.rules = lib.mapAttrsToList (
      instanceName: _:
      "d ${config.hostSpec.home}/.config/easytier 0755 ${config.hostSpec.username} ${
        config.users.users.${config.hostSpec.username}.group
      } -"
    ) hostEasytier;

    # Enable IP forwarding for EasyTier (use mkDefault to avoid conflicts)
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = lib.mkDefault 1;
      "net.ipv6.conf.all.forwarding" = lib.mkDefault 1;
    };
  };
}
