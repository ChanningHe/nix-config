{
  config,
  inputs,
  isDarwin,
  lib,
  ...
}:
let
  isLinux = !isDarwin;
  mail = config.hostSpec.serviceInfo.mail;
  mailEnabled = config.hostSpec.serviceInfo ? mail && mail.enable;
  sharedSopsFile = "${inputs.nix-secrets}/secrets/shared.yaml";
in
lib.optionalAttrs isLinux {
  config = lib.mkIf mailEnabled {
    assertions = [
      {
        assertion = builtins.pathExists sharedSopsFile;
        message = "msmtp is enabled, but ${sharedSopsFile} does not exist.";
      }
    ];

    sops.secrets."msmtp/password" = {
      sopsFile = sharedSopsFile;
      mode = "0400";
    };

    programs.msmtp = {
      enable = true;
      setSendmail = true;

      defaults = {
        inherit (mail)
          auth
          port
          tls
          tls_starttls
          ;
        syslog = "LOG_MAIL";
        timeout = 30;
      };

      accounts.default = {
        inherit (mail) host user from;
        passwordeval = "cat ${config.sops.secrets."msmtp/password".path}";
      };
    };
  };
}
