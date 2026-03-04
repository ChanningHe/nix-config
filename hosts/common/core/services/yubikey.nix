{
  pkgs,
  lib,
  config,
  isDarwin,
  ...
}:
let
  isLinux = !isDarwin;
  homeDirectory =
    if isLinux then "/home/${config.hostSpec.username}" else "/Users/${config.hostSpec.username}";
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
// lib.optionalAttrs isLinux {
  services.pcscd.enable = true;
  services.udev.packages = [ pkgs.yubikey-personalization ];

  security.pam = {
    rssh.enable = true;
    sshAgentAuth.enable = true;
    u2f = {
      enable = true;
      settings = {
        cue = true; # Tells user they need to press the button
        authFile = "${homeDirectory}/.config/Yubico/u2f_keys";
      };
    };
    services = {
      login.u2fAuth = true;
      sudo = {
        rssh = true;
        u2fAuth = true;
        sshAgentAuth = true; # Use SSH_AUTH_SOCK for sudo
      };
    };
  };
}
