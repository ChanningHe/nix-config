# System-level niri Wayland compositor and desktop infrastructure.
# Provides: display manager, compositor, polkit, keyring, XDG portals, XWayland compat.
{ pkgs, inputs, ... }:
{
  imports = [
    inputs.niri.nixosModules.niri
  ];

  programs.niri.enable = true;
  # Use nixpkgs niri (pre-built in NixOS cache) instead of flake's niri-stable
  programs.niri.package = pkgs.niri;

  # ── Display Manager (greetd) ─────────────────────────
  # Without a display manager, the system boots to a bare TTY.
  # greetd is a lightweight login manager that launches the niri session.
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --remember --remember-session --sessions ${pkgs.niri}/share/wayland-sessions";
        user = "greeter";
      };
    };
  };

  # Polkit: permission elevation dialogs (like macOS "enter password to allow")
  security.polkit.enable = true;

  # GNOME Keyring: credential storage (like macOS Keychain)
  services.gnome.gnome-keyring.enable = true;
  # Disable GCR SSH agent — conflicts with programs.ssh.startAgent from core/ssh.nix
  services.gnome.gcr-ssh-agent.enable = false;

  # XDG Portal: app integration (file pickers, screenshots, screen sharing)
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gtk
      xdg-desktop-portal-gnome
    ];
    config.niri = {
      default = [
        "gnome"
        "gtk"
      ];
      "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];
    };
  };

  # Make Electron/Chromium apps use native Wayland instead of XWayland
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  environment.systemPackages = with pkgs; [
    xwayland-satellite # X11 app compatibility layer — niri integrates it automatically
    wl-clipboard # Wayland clipboard utilities (wl-copy / wl-paste)
  ];
}
