{ pkgs, ... }:
{
  imports = [
    #################### Required Configs ####################
    common/core # required

    #################### Host-specific Optional Configs ####################
    # FIXME(starter): add or remove any optional config directories or files here
  ];

  # FIXME(starter): you can also add packages that don't require any delcarative configuration below
  home.packages = builtins.attrValues {
    inherit (pkgs)
      vlc # media player
      ;
  };
}
