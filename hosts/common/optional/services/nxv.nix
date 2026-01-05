# nxv - Nix Version Index Service
# Provides a web UI and REST API for searching package versions across nixpkgs history
# See: https://github.com/jamesbrink/nxv
{
  config,
  lib,
  inputs,
  ...
}:
let
  hostName = config.hostSpec.hostName;
  hostNetwork = config.hostSpec.networkInfo.hosts.${hostName} or { };

  # Extract nxv service configuration from hostSpec
  nxvConfig = hostNetwork.nxv or { };
  nxvEnabled = nxvConfig.enable or false;
in
{
  imports = [
    inputs.nxv.nixosModules.default
  ];

  config = lib.mkIf nxvEnabled {
    services.nxv = {
      enable = true;

      # Network configuration
      host = nxvConfig.host or "127.0.0.1";
      port = nxvConfig.port or 32729;

      # Storage
      dataDir = nxvConfig.dataDir or "/var/lib/nxv";

      # Security & CORS
      cors.enable = nxvConfig.cors.enable or false;
      #openFirewall = nxvConfig.openFirewall or false;

      # Auto-update index daily
      autoUpdate = {
        enable = nxvConfig.autoUpdate.enable or true;
        interval = nxvConfig.autoUpdate.interval or "daily";
      };
    };
  };
}
