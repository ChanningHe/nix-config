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

  # ── Power / Idle ──────────────────────────────────────
  # gsd-power ships upstream defaults sleep-inactive-ac-type='suspend' with
  # sleep-inactive-ac-timeout=900, so an idle desktop suspends after 15 min and
  # drops off the network. These are workstations/servers that must stay
  # reachable, so never suspend on idle. Screen blanking
  # (org.gnome.desktop.session idle-delay) is left at its default.
  services.desktopManager.gnome.extraGSettingsOverrides = ''
    [org.gnome.settings-daemon.plugins.power]
    sleep-inactive-ac-type='nothing'
    sleep-inactive-battery-type='nothing'
  '';
  services.desktopManager.gnome.extraGSettingsOverridePackages = [ pkgs.gnome-settings-daemon ];

  # Useful GNOME extras not included by default
  environment.systemPackages = with pkgs; [
    gnome-tweaks
    dconf-editor
  ];
}
