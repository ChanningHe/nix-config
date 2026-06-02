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

  # This overlay currently contributes nothing. Two traps if you ever add Linux-only
  # package modifications here:
  #   1. Do NOT use `lib.mkIf` — an overlay must return a plain attrset. `mkIf` returns
  #      a module node `{ _type = "if"; ... }` that poisons pkgs (collapses to {} during
  #      module property-discharge, e.g. breaking NixOS manual / options.json eval).
  #   2. Do NOT branch on `final.stdenv` — eagerly forcing stdenv through the overlay's
  #      own fixpoint causes infinite recursion. Use `prev.stdenv.hostPlatform.isLinux`.
  linuxModifications = _final: _prev: { };

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
