# User config applicable to both nixos and darwin
{
  inputs,
  pkgs,
  config,
  lib,
  ...
}:
let
  inherit (config) hostSpec;
  inherit (hostSpec) username;
  # Every file in dir holds one entry
  readEntries = dir: map (f: lib.trim (builtins.readFile f)) (lib.filesystem.listFilesRecursive dir);
  # One `pamu2fcfg -n -o pam://shoal-pam -i pam://shoal-pam` output per YubiKey
  u2fCreds = map (lib.removePrefix ":") (readEntries ./u2f);
in
{
  # Read by pam_u2f, see services/yubikey.nix
  environment.etc."u2f_mappings".text = lib.concatStringsSep ":" ([ username ] ++ u2fCreds) + "\n";

  users.users.${username} = {
    name = username;
    # bashInteractive, not pkgs.bash: the latter is the non-readline build.
    shell = pkgs.bashInteractive;

    # These get placed into /etc/ssh/authorized_keys.d/<name> on nixos
    openssh.authorizedKeys.keys = readEntries ./keys;
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    # important: disable global comp init
    # or else it'll be slow zsh startup with marlonrichert/zsh-autocomplete
    # referenced from: https://www.reddit.com/r/NixOS/comments/15zhf37/do_you_have_loading_delay_with_zsh/
    enableGlobalCompInit = false;
  };

  # No matter what environment we are in we want these tools
  environment.systemPackages = [
    pkgs.just
    pkgs.rsync
  ];
}
# Import the user's personal/home configurations, unless the environment is minimal
// lib.optionalAttrs (inputs ? "home-manager") {
  home-manager = {
    extraSpecialArgs = {
      inherit pkgs inputs;
      hostSpec = config.hostSpec;
    };
    users.${hostSpec.username}.imports = lib.flatten (
      lib.optional (!hostSpec.isMinimal) [
        (
          { config, ... }:
          import (lib.custom.relativeToRoot "home/${hostSpec.username}/${hostSpec.hostName}.nix") {
            inherit
              pkgs
              inputs
              config
              lib
              hostSpec
              ;
          }
        )
      ]
    );
  };
}
