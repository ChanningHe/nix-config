# GNOME Desktop Environment (Wayland).
# Provides a full-featured DE as an alternative to niri.
# Session appears in greetd alongside niri for user selection at login.
{ pkgs, ... }:
{
  services.xserver.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  # We use greetd, not GDM
  services.xserver.displayManager.gdm.enable = false;

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
