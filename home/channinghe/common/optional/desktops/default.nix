{ pkgs, ... }:
{
  imports = [
    ########## Desktop Shell ##########
    ./niri.nix
    ./noctalia.nix

    ########## Utilities ##########
    ./gtk.nix
    ./playerctl.nix
    ./ime.nix
    ./fonts.nix
  ];
  home.packages = with pkgs; [
    pavucontrol # GUI audio mixer (pairs with PipeWire)
    galculator # GTK calculator
    nautilus # file manager
  ];
}
