# FIXME(starter): this is an example of how a secondary user called "exampleSecondUser" can be declared.
# NOTE that this file's parent directory matches the username!
# Modify the directory name and all instances of `exampleSecondUser` in this file to a real username to
# make use of this file. You'll also need to import this file in the relevant `nix-config/hosts/[platform]/[hostname]/default.nix`
# host file for the user to be created on the host.
# NOTE that this file also assumes you will be declaring the user's password via sops.
# .
# If you have no need for secondary users, simply delete this file and its parent directory, and ensure that
# your `nix-config/hosts/[platform]/[hostname]/default.nix` files do not import this file. You'll also want
# to delete the related home-level directory located at`nix-config/home/exampleSecondUser`

#
# Basic user for viewing exampleSecondUser
#

{
  inputs,
  lib,
  pkgs,
  config,
  ...
}:
let
  hostSpec = config.hostSpec;
  secretsSubPath = "passwords/exampleSecondUser";
in
{
  # Decrypt passwords/exampleSecondUser to /run/secrets-for-users/ so it can be used to create the user
  sops.secrets.${secretsSubPath}.neededForUsers = true;
  users.mutableUsers = false; # Required for password to be set via sops during system activation!

  users.users.exampleSecondUser = {
    isNormalUser = true;
    hashedPasswordFile = config.sops.secrets.${secretsSubPath}.path;
    shell = pkgs.zsh; # default shell
    extraGroups = [
      "audio"
      "video"
    ];

    packages = [ pkgs.home-manager ];
  };
}
# Import this user's personal/home configurations
// lib.optionalAttrs (inputs ? "home-manager") {
  home-manager = {
    extraSpecialArgs = {
      inherit pkgs inputs;
      hostSpec = config.hostSpec;
    };
    users.exampleSecondUser.imports = lib.flatten (
      lib.optional (!hostSpec.isMinimal) [
        (
          { config, ... }:
          import (lib.custom.relativeToRoot "home/exampleSecondUser/${hostSpec.hostName}.nix") {
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
