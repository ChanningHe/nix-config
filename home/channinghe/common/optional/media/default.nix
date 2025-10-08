# FIXME(starter): add/edit any optional, media related pkgs here
{ pkgs, ... }:
{
  #imports = [ ./foo.nix ];

  home.packages = builtins.attrValues {
    inherit (pkgs)
      vlc
      ;
  };
}
