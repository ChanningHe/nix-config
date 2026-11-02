# Niri: scrollable-tiling Wayland compositor.
# Only niri-specific config lives here; shared desktop infra is in default.nix.
{ pkgs, inputs, ... }:
{
  imports = [
    inputs.niri.nixosModules.niri
  ];

  programs.niri.enable = true;
  programs.niri.package = pkgs.niri;
  # niri comes from nixpkgs (cache.nixos.org); niri.cachix.org would never hit
  niri-flake.cache.enable = false;

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
