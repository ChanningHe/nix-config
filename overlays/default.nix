#
# This file defines overlays/custom modifications to upstream packages
#

{ inputs, lib, ... }:

let
  # Add in custom packages from this config. Directory layout and dispatch
  # rules (common, per-platform, per-arch) live in lib/scan-packages.nix so the
  # `packages` flake output and this overlay agree on what's exposed where.
  additions =
    final: prev:
    lib.custom.scanPackages {
      pkgs = final;
      # Read platform from prev to avoid fixpoint recursion on final.stdenv.
      hostPlatform = prev.stdenv.hostPlatform;
      root = ../pkgs;
    };

  # Linux-only package overrides (EmergentMind/nix-config pattern). Uncomment an entry
  # to pull that package from the unstable channel on Linux.
  linuxModifications =
    final: prev:
    prev.lib.optionalAttrs prev.stdenv.isLinux {
      # neovim = final.unstable.neovim;
      # neovide = final.unstable.neovide;
      # vimPlugins = final.unstable.vimPlugins;
    };

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
