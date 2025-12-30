# NUT (Network UPS Tools) Configuration
#
# Manages UPS devices for power protection and graceful shutdown.
# Configuration is imported from nix-secrets/nix/services.nix
#
# Modes:
# - standalone: Local UPS with driver + upsd + upsmon (this host owns the UPS)
# - netserver: Like standalone but accepts remote connections
# - netclient: Remote monitoring only (UPS is on another host)
#
# Required sops secrets (in host's yaml file):
# - ups/upsmon-password: Password for upsmon user (used by local and remote monitors)

{
  config,
  lib,
  inputs,
  ...
}:
let
  hostName = config.hostSpec.hostName;
  upsInfo = config.hostSpec.serviceInfo.${hostName}.ups or null;

  # Check if this host has UPS configuration
  hasUpsConfig = upsInfo != null;

  # Get UPS names from configuration
  upsNames = lib.attrNames (upsInfo.ups or { });
  firstUpsName = if upsNames != [ ] then lib.head upsNames else null;

  # Sops secrets folder
  sopsFolder = builtins.toString inputs.nix-secrets + "/secrets";
in
{
  config = lib.mkIf hasUpsConfig {
    # Declare UPS password secret
    sops.secrets."ups/upsmon-password" = {
      sopsFile = "${sopsFolder}/${hostName}.yaml";
      mode = "0400";
    };

    power.ups = {
      enable = true;
      mode = upsInfo.mode or "standalone";

      # UPS device definitions (from secrets)
      ups = upsInfo.ups or { };

      # upsd server configuration
      upsd = lib.mkIf (upsInfo ? upsd) {
        enable = true;
        listen = upsInfo.upsd.listen or [ ];
        extraConfig = upsInfo.upsd.extraConfig or "";
      };

      # Users that can access upsd (for upsmon and remote clients)
      users = (upsInfo.users or { }) // {
        # Default upsmon user for local monitoring
        upsmon = {
          passwordFile = config.sops.secrets."ups/upsmon-password".path;
          upsmon = "primary";
        };
      };

      # Local upsmon configuration
      upsmon = lib.mkIf (firstUpsName != null) {
        enable = true;
        monitor.${firstUpsName} = {
          system = firstUpsName;
          user = "upsmon";
          passwordFile = config.sops.secrets."ups/upsmon-password".path;
          type = "primary";
          powerValue = 1;
        };
        settings = upsInfo.upsmon.settings or { };
      };

      # Open firewall for upsd if netserver mode
      #openFirewall = (upsInfo.mode or "standalone") == "netserver";
    };
  };
}
