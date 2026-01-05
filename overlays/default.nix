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

  linuxModifications = final: prev: prev.lib.mkIf final.stdenv.isLinux { };

  modifications = final: prev: {
    # example = prev.example.overrideAttrs (oldAttrs: let ... in {
    # ...
    # });
  };

  stable-packages = final: _prev: {
    stable = import inputs.nixpkgs-stable {
      system = final.stdenv.hostPlatform.system;
      config.allowUnfree = true;
      #overlays = [
      #];
    };
  };

  unstable-packages = final: _prev: {
    unstable = import inputs.nixpkgs-unstable {
      system = final.stdenv.hostPlatform.system;
      config.allowUnfree = true;
      #overlays = [
      #];
    };
  };

  # Proxmox VE overlay - only available on x86_64-linux
  proxmox-overlay =
    final: prev:
    if prev.stdenv.hostPlatform.system == "x86_64-linux" then
      inputs.proxmox-nixos.overlays.${prev.stdenv.hostPlatform.system} final prev
    else
      { };

  # nxv - Nix version index CLI
  # Provides fast package version search across nixpkgs history
  nxv-overlay = final: prev: inputs.nxv.overlays.default final prev;

in
{
  default =
    final: prev:

    (additions final prev)
    // (modifications final prev)
    // (linuxModifications final prev)
    // (stable-packages final prev)
    // (unstable-packages final prev)
    // (proxmox-overlay final prev)
    // (nxv-overlay final prev);
}
