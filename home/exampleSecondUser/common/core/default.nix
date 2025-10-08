# FIXME(starter): this is an example of how a secondary user called "exampleSecondUser" can be declared at the home-manager level.
# NOTE that the files here roll up to parent directory that matches the username!
# Modify the directory name and all instances of `exampleSecondUser` in that directories child files to a real username to
# make practical use of them.
# If you have no need for secondary users, simply delete the user's directory from nix-confgi/home, and ensure that
# your `nix-config/hosts/[platform]/[hostname]/default.nix` files do not import the respective host level files.
# See the instructions for `nix-config/hosts/nixos/hostname1/default.nix` for additional info.

#
# Basic user for viewing exampleSecondUser
#

{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = lib.flatten [
    (lib.custom.scanPaths ./.)
    (map lib.custom.relativeToRoot [
      "modules/home"
    ])
  ];

  home = {
    username = lib.mkDefault "exampleSecondUser";
    homeDirectory = lib.mkDefault "/home/${config.home.username}";
    stateVersion = lib.mkDefault "24.11";
    sessionPath = [ "$HOME/.local/bin" ];
  };

  home.packages = builtins.attrValues {
    inherit (pkgs)

      # Packages that don't have custom configs go here
      nix-tree
      ;
  };

  nix = {
    package = lib.mkDefault pkgs.nix;
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      warn-dirty = false;
    };
  };

  programs = {
    home-manager.enable = true;
  };

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";
}
