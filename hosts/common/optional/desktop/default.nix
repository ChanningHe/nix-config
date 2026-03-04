# System-level desktop environment entry point.
# Shared infrastructure: display manager, polkit, keyring, portals, fonts.
# Desktop-specific configs (niri, gnome) are in their own files.
{ pkgs, ... }:
{
  imports = [
    ./niri.nix
    ./gnome.nix
    ./i18n.nix
  ];

  # ── Shared Security & Credential Services ─────────────
  security.polkit.enable = true;
  services.gnome.gnome-keyring.enable = true;
  services.gnome.gcr-ssh-agent.enable = false;

  # ── XDG Portals (shared base) ─────────────────────────
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gtk
      xdg-desktop-portal-gnome
    ];
  };

  # Electron/Chromium native Wayland
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  # ── System Fonts ──────────────────────────────────────
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
    noto-fonts-color-emoji
  ];

  environment.systemPackages = with pkgs; [
    ghostty
    wl-clipboard
    polkit_gnome
  ];

  # Polkit agent for standalone compositors (niri, sway, etc.)
  # GNOME has its own built-in agent, so this only activates for non-GNOME sessions.
  systemd.user.services.polkit-gnome-agent = {
    description = "GNOME Polkit Authentication Agent";
    wantedBy = [ "graphical-session.target" ];
    wants = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
      Restart = "on-failure";
      RestartSec = 1;
      TimeoutStopSec = 10;
    };
  };
}
