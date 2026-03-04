# Niri: scrollable-tiling Wayland compositor.
# Only niri-specific config lives here; shared desktop infra is in default.nix.
{ pkgs, inputs, ... }:
{
  imports = [
    inputs.niri.nixosModules.niri
  ];

  programs.niri.enable = true;
  programs.niri.package = pkgs.niri;

  # XDG portal routing rules specific to niri
  xdg.portal.config.niri = {
    default = [
      "gnome"
      "gtk"
    ];
    "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];
  };

  environment.systemPackages = with pkgs; [
    xwayland-satellite # X11 app compat — niri integrates it automatically
  ];
}
