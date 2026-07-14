# Generic standalone home-manager profile for any Linux host with nix.
# Not tied to a fleet host — activated through the flake's homeConfigurations
# output instead of the per-host NixOS/Darwin home-manager wiring:
#   just home
#   home-manager switch --flake .#channinghe@x86_64-linux -b bk
{ pkgs, ... }:
{
  imports = [
    #
    # ========== Required Configs ==========
    #
    common/core

    #
    # ========== Generic Optional Configs ==========
    #
    #common/optional/llm-agents.nix
  ];

  # Session variable / XDG integration fixes for non-NixOS distros
  # (Ubuntu, Debian, Arch, ...). Extra session vars are harmless on NixOS.
  targets.genericLinux.enable = true;

  # Foreign distros lack the nix-built glibc locale archive, which breaks
  # locale-aware tools with "Failed to set locale" warnings. UTF-8 variant
  # only — full glibcLocales is ~10x larger and core sets LANG=en_US.UTF-8.
  home.sessionVariables.LOCALE_ARCHIVE = "${pkgs.glibcLocalesUtf8}/lib/locale/locale-archive";
}
