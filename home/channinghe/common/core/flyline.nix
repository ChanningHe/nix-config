# flyline: bash line editor (https://github.com/HalFrgrd/flyline)
#
# The pure-shell configuration lives in dotfiles (~/.config/flyline/,
# symlinked by the dotfiles module) so it works on non-nix hosts too.
# This module only pins the exact store paths and sources it.
{
  lib,
  pkgs,
  inputs,
  ...
}:
let
  flyline = inputs.flyline.packages.${pkgs.stdenv.hostPlatform.system}.default;
  flylineLib = "libflyline.${if pkgs.stdenv.hostPlatform.isDarwin then "dylib" else "so"}";
in
{
  # Order 2000: after bash-completion and the rest of initExtra
  programs.bash.initExtra = lib.mkOrder 2000 ''
    FLYLINE_LIB=${flyline}/lib/${flylineLib}
    [ -f ~/.config/flyline/flyline.bash ] && source ~/.config/flyline/flyline.bash
  '';

  # flyline covers history search and suggestions
  programs.atuin.enableBashIntegration = false;
  programs.zoxide.enableBashIntegration = false;
}
