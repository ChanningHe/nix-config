{
  pkgs,
  lib,
  config,
  ...
}:
let
  homeDirectory =
    if pkgs.stdenv.isLinux then
      "/home/${config.hostSpec.username}"
    else
      "/Users/${config.hostSpec.username}";
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

  services.pcscd.enable = pkgs.stdenv.isLinux;

  security.pam = lib.optionalAttrs pkgs.stdenv.isLinux {
    rssh.enable = true;
    services.sudo.rssh = true;
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
        u2fAuth = true;
        sshAgentAuth = true; # Use SSH_AUTH_SOCK for sudo
      };
    };
  };
}
