#
# This file defines overlays/custom modifications to upstream packages
#

{ inputs, ... }:

let
  # Add in custom packages from this config
  additions =
    final: prev:
    (prev.lib.packagesFromDirectoryRecursive {
      callPackage = prev.lib.callPackageWith final;
      directory = ../pkgs/common;
    });

  # NOTE: an overlay must return a plain attrset of packages. `lib.mkIf` returns a
  # module-system node `{ _type = "if"; condition; content; }`, which poisons pkgs:
  # any code that runs module property-discharge over pkgs collapses the whole set to
  # `content` ({}), making packages like `nixos-test-driver` vanish and breaking eval
  # (e.g. NixOS manual / options.json generation). Use `optionalAttrs` for a conditional
  # package set instead.
  linuxModifications = final: prev: prev.lib.optionalAttrs final.stdenv.isLinux { };

  modifications = final: prev: {
    # example = prev.example.overrideAttrs (oldAttrs: let ... in {
    # ...
    # });
  };

  unstable-packages = final: _prev: {
    unstable = import inputs.nixpkgs-unstable {
      system = final.stdenv.hostPlatform.system;
      config.allowUnfree = true;
    };
  };

in
{
  default =
    final: prev:

    (additions final prev)
    // (modifications final prev)
    // (linuxModifications final prev)
    // (unstable-packages final prev);
}
