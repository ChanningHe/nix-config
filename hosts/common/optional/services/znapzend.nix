{
  config,
  lib,
  ...
}:
let
  hostName = config.hostSpec.hostName;
  znapzendInfo = config.hostSpec.serviceInfo.${hostName}.znapzend or { };
  isEnabled = znapzendInfo.enable or false;
in
{
  config = lib.mkIf isEnabled {
    services.znapzend = {
      enable = true;

      # Global settings with sensible defaults
      pure = znapzendInfo.pure or false;
      autoCreation = znapzendInfo.autoCreation or false;
      noDestroy = znapzendInfo.noDestroy or false;
      logLevel = znapzendInfo.logLevel or "info";
      logTo = znapzendInfo.logTo or "syslog::daemon";
      mailErrorSummaryTo = znapzendInfo.mailErrorSummaryTo or "";

      # Feature flags
      features = {
        compressed = znapzendInfo.features.compressed or false;
        sendRaw = znapzendInfo.features.sendRaw or false;
        skipIntermediates = znapzendInfo.features.skipIntermediates or false;
        lowmemRecurse = znapzendInfo.features.lowmemRecurse or false;
        oracleMode = znapzendInfo.features.oracleMode or false;
        recvu = znapzendInfo.features.recvu or false;
        zfsGetType = znapzendInfo.features.zfsGetType or false;
      };

      # Per-dataset backup configurations
      zetup = znapzendInfo.zetup or { };
    };
  };
}
