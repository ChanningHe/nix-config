# NUT (Network UPS Tools) Configuration
#
# Importing this file activates UPS management for the current host.
# Host-level configuration lives in nix-secrets/nix/services.nix under
# serviceInfo.<hostName>.ups; the host MUST provide that block.
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
  pkgs,
  ...
}:
let
  hostName = config.hostSpec.hostName;
  upsInfo = config.hostSpec.serviceInfo.${hostName}.ups;
  firstUpsName = lib.head (lib.attrNames upsInfo.ups);

  sopsFolder = "${inputs.nix-secrets}/secrets";

  mail = config.hostSpec.serviceInfo.mail;
  notifyEnabled = mail.enable && mail.recipients != [ ];

  notifyScript = pkgs.writeShellApplication {
    name = "ups-notify";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      # Invoked by upsmon NOTIFYCMD on events flagged EXEC.
      # $1: human-readable message (NOTIFYMSG expanded by upsmon)
      # env: NOTIFYTYPE (e.g. ONBATT), UPSNAME (e.g. apc@localhost)
      msg="''${1:-}"
      evt="''${NOTIFYTYPE:-UNKNOWN}"
      ups="''${UPSNAME:-unknown}"
      host="${hostName}"
      from="${mail.from}"
      to="${lib.concatStringsSep "," mail.recipients}"

      {
        printf 'From: %s\n' "$from"
        printf 'To: %s\n'   "$to"
        printf 'Subject: [UPS][%s] %s on %s\n' "$host" "$evt" "$ups"
        printf '\n'
        printf 'Host : %s\n' "$host"
        printf 'UPS  : %s\n' "$ups"
        printf 'Event: %s\n' "$evt"
        printf 'Time : %s\n' "$(date -Is)"
        printf '\nMessage:\n%s\n' "$msg"
      } | /run/wrappers/bin/sendmail -t
    '';
  };

  # Default NOTIFYFLAG set for critical events. Per-host overrides via
  # upsInfo.upsmon.settings win (see merge below).
  defaultNotifySettings = lib.optionalAttrs notifyEnabled {
    NOTIFYCMD = "${notifyScript}/bin/ups-notify";
    NOTIFYFLAG = [
      [
        "ONLINE"
        "SYSLOG+EXEC"
      ]
      [
        "ONBATT"
        "SYSLOG+WALL+EXEC"
      ]
      [
        "LOWBATT"
        "SYSLOG+WALL+EXEC"
      ]
      [
        "FSD"
        "SYSLOG+WALL+EXEC"
      ]
      [
        "COMMOK"
        "SYSLOG+EXEC"
      ]
      [
        "COMMBAD"
        "SYSLOG+EXEC"
      ]
      [
        "NOCOMM"
        "SYSLOG+EXEC"
      ]
      [
        "REPLBATT"
        "SYSLOG+EXEC"
      ]
      [
        "SHUTDOWN"
        "SYSLOG+WALL+EXEC"
      ]
    ];
  };
in
{
  sops.secrets."ups/upsmon-password" = {
    sopsFile = "${sopsFolder}/${hostName}.yaml";
    mode = "0400";
  };

  power.ups = {
    enable = true;
    mode = upsInfo.mode;

    ups = upsInfo.ups;

    upsd = lib.mkIf (upsInfo ? upsd) {
      enable = true;
      listen = upsInfo.upsd.listen;
      extraConfig = upsInfo.upsd.extraConfig or "";
    };

    users = (upsInfo.users or { }) // {
      upsmon = {
        passwordFile = config.sops.secrets."ups/upsmon-password".path;
        upsmon = "primary";
      };
    };

    upsmon = {
      enable = true;
      monitor.${firstUpsName} = {
        system = firstUpsName;
        user = "upsmon";
        passwordFile = config.sops.secrets."ups/upsmon-password".path;
        type = upsInfo.upsmon.type;
        powerValue = 1;
      };
      # Per-host settings override module defaults.
      settings = defaultNotifySettings // (upsInfo.upsmon.settings or { });
    };
  };

  # Upstream NixOS ups module sets no Restart= on any unit, so a transient
  # SNMP outage at boot leaves upsdrv.service stuck `failed`. Restart=on-failure
  # works on Type=oneshot since systemd >=244; StartLimitIntervalSec=0 disables
  # the default 5-restarts-in-10s rate limit.
  systemd.services.upsdrv = {
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "30s";
    };
    unitConfig.StartLimitIntervalSec = 0;
  };
  systemd.services.upsd = {
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "10s";
    };
    unitConfig.StartLimitIntervalSec = 0;
  };
  systemd.services.upsmon = {
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "10s";
    };
    unitConfig.StartLimitIntervalSec = 0;
  };
}
