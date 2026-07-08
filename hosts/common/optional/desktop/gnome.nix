# GNOME Desktop Environment (Wayland).
# Provides a full-featured DE as an alternative to niri.
# Session appears in greetd alongside niri for user selection at login.
{ pkgs, ... }:
{
  services.xserver.enable = true;
  services.desktopManager.gnome.enable = true;

  # GDM: native GNOME display manager, discovers both GNOME and niri sessions.
  # gdm.wayland removed in GNOME 50 — Wayland is now the only session and setting
  # this option (even to `true`) trips a NixOS assertion.
  services.displayManager.gdm.enable = true;

  # XDG portal routing for GNOME sessions
  xdg.portal.config.gnome = {
    default = [
      "gnome"
      "gtk"
    ];
  };

  # Strip GNOME bloat — remove apps we don't need
  environment.gnome.excludePackages = with pkgs; [
    epiphany # web browser (we have our own)
    geary # email client
    gnome-music
    gnome-tour
    gnome-contacts
    gnome-maps
    gnome-weather
    totem # video player
    yelp # help viewer
    simple-scan
  ];

  # Useful GNOME extras not included by default
  environment.systemPackages = with pkgs; [
    gnome-tweaks
    dconf-editor
  ];
}
