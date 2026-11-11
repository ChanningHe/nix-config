{
  pkgs,
  lib,
  config,
  isDarwin,
  ...
}:
let
  isLinux = !isDarwin;
  inherit (config.hostSpec) username;

  # One origin for every host, so a single pamu2fcfg registration works everywhere.
  u2fOrigin = "pam://shoal-pam";
  u2fAuthFile = "/etc/u2f_mappings";

  # Only hardware-backed keys may authorize sudo; plain login keys must not.
  sudoKeys =
    lib.filter (lib.hasPrefix "sk-")
      config.users.users.${username}.openssh.authorizedKeys.keys;
in
{
  environment.systemPackages = builtins.attrValues {
    inherit (pkgs)
      age-plugin-yubikey
      #yubioath-flutter # gui-based authenticator tool. yubioath-desktop on older nixpkg channels
      yubikey-manager # cli-based authenticator tool. accessed via `ykman`
      pam_u2f # for yubikey with sudo
      ;
  };
}
// lib.optionalAttrs isDarwin {
  environment.etc."pam.d/sudo_local".text = ''
    # YubiKey auth
    auth       sufficient     ${pkgs.pam_u2f}/lib/security/pam_u2f.so authfile=${u2fAuthFile} origin=${u2fOrigin} appid=${u2fOrigin} cue [cue_prompt=Touch YubiKey for sudo]
    # Fallback to Touch ID
    auth       sufficient     pam_tid.so
  '';
}
// lib.optionalAttrs isLinux {
  services.pcscd.enable = true;
  services.udev.packages = [ pkgs.yubikey-personalization ];

  environment.etc."ssh/sudo_keys.d/${username}".text = lib.concatLines (map lib.trim sudoKeys);

  security.pam = {
    rssh = {
      enable = true;
      settings.auth_key_file = "/etc/ssh/sudo_keys.d/$ruser";
    };
    u2f = {
      enable = true;
      settings = {
        cue = true; # Tells user they need to press the button
        authfile = u2fAuthFile;
        origin = u2fOrigin;
        appid = u2fOrigin;
      };
    };
    services = {
      login.u2fAuth = true;
      sudo = {
        rssh = true; # ssh-agent signature, works over ssh with a forwarded agent
        u2fAuth = true; # local YubiKey
      };
    };
  };
}
