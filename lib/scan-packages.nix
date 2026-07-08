# Platform/arch-aware package tree scanner, exposed as `lib.custom.scanPackages`.
#
# Given a root directory laid out as:
#
#   <root>/common/                  → every system
#   <root>/nixos/common/            → every Linux system
#   <root>/nixos/x86_64/            → x86_64-linux only
#   <root>/nixos/aarch64/           → aarch64-linux only
#   <root>/darwin/common/           → every Darwin system
#   <root>/darwin/x86_64/           → x86_64-darwin only
#   <root>/darwin/aarch64/          → aarch64-darwin only
#
{ lib }:
{
  pkgs,
  hostPlatform ? pkgs.stdenv.hostPlatform,
  root,
}:
let
  hp = hostPlatform;

  scanIfExists =
    subdir:
    let
      path = root + "/${subdir}";
    in
    lib.optionalAttrs (builtins.pathExists path) (
      lib.packagesFromDirectoryRecursive {
        callPackage = lib.callPackageWith pkgs;
        directory = path;
      }
    );
in
scanIfExists "common"
// lib.optionalAttrs hp.isLinux (scanIfExists "nixos/common")
// lib.optionalAttrs (hp.isLinux && hp.isx86_64) (scanIfExists "nixos/x86_64")
// lib.optionalAttrs (hp.isLinux && hp.isAarch64) (scanIfExists "nixos/aarch64")
// lib.optionalAttrs hp.isDarwin (scanIfExists "darwin/common")
// lib.optionalAttrs (hp.isDarwin && hp.isx86_64) (scanIfExists "darwin/x86_64")
// lib.optionalAttrs (hp.isDarwin && hp.isAarch64) (scanIfExists "darwin/aarch64")
