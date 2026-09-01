# NOTE(starter): this is the primary user across all hosts. The username for primary is defined in hostSpec,
# and is declared in `nix-config/common/core/default.nix`

# User config applicable to both nixos and darwin
{
  inputs,
  pkgs,
  config,
  lib,
  ...
}:
let
  hostSpec = config.hostSpec;
  pubKeys = lib.filesystem.listFilesRecursive ./keys;
in
{
  users.users.${hostSpec.username} = {
    name = hostSpec.username;
    # bashInteractive, not pkgs.bash: the latter is the non-readline build.
    shell = pkgs.bashInteractive;

    # These get placed into /etc/ssh/authorized_keys.d/<name> on nixos
    openssh.authorizedKeys.keys = lib.lists.forEach pubKeys (key: builtins.readFile key);
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
