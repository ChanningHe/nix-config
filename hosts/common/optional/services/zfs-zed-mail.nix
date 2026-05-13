{
  config,
  isDarwin,
  lib,
  ...
}:
let
  isLinux = !isDarwin;
  mail = config.hostSpec.serviceInfo.mail;
  zfs = mail.zfs;
  hasZfsFileSystem = lib.any (fs: fs.fsType == "zfs") (lib.attrValues config.fileSystems);
in
lib.optionalAttrs isLinux {
  assertions = [
    {
      assertion = hasZfsFileSystem;
      message = "zfs-zed-mail.nix was imported on ${config.hostSpec.hostName}, but no ZFS filesystems are configured.";
    }
    {
      assertion = mail.enable;
      message = "zfs-zed-mail.nix requires hostSpec.serviceInfo.mail.enable = true.";
    }
    {
      assertion = mail.recipients != [ ];
      message = "zfs-zed-mail.nix requires hostSpec.serviceInfo.mail.recipients.";
    }
  ];

  services.zfs.zed = {
    enableMail = true;
    settings = {
      ZED_EMAIL_ADDR = mail.recipients;
      ZED_NOTIFY_VERBOSE = zfs.notifyVerbose;
      ZED_NOTIFY_INTERVAL_SECS = zfs.notifyIntervalSecs;
    };
  };
}
