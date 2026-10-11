{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Fixed calendar slots (~10 days apart) instead of OnUnitActiveSec=10d:
  # monotonic timers restart on every boot, so a host reboot would also trigger
  # a BMC reset. OnCalendar + Persistent survives reboots deterministically.
  schedule = "*-*-01,11,21 04:00:00";
in
{
  assertions = [
    {
      assertion = lib.elem "ipmi_devintf" config.boot.kernelModules;
      message = "ipmi-bmc-reset.nix needs /dev/ipmi0; also import hosts/common/optional/system/ipmi.nix on ${config.hostSpec.hostName}.";
    }
  ];

  # Periodic BMC cold reset to recover from slow BMC memory leaks / hung web UI.
  # Only restarts the management controller; the host OS keeps running.
  systemd.services.ipmi-bmc-reset = {
    description = "Cold reset the BMC via in-band IPMI";
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.ipmitool}/bin/ipmitool mc reset cold";
    };
  };

  systemd.timers.ipmi-bmc-reset = {
    description = "Periodic BMC cold reset";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = schedule;
      Persistent = true;
      RandomizedDelaySec = "15m";
    };
  };
}
