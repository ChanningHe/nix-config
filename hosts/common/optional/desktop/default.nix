# System-level desktop environment entry point.
# Imports NixOS-only modules: compositor, display manager, locale.
# User-level configs (GTK, fonts, IME, noctalia) belong in home/.../desktops/.
{ pkgs, ... }:
{
  imports = [
    ./niri.nix
    ./i18n.nix
  ];

  environment.systemPackages = with pkgs; [
    ghostty
  ];

  # System-level fonts (available to display manager and all users)
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
    noto-fonts-color-emoji
  ];

}
