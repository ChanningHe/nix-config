# User-level fontconfig preferences.
# Font packages are installed system-wide in hosts/common/optional/desktop/niri.nix.
{ ... }:
{
  fonts.fontconfig = {
    enable = true;
    defaultFonts = {
      sansSerif = [
        "Noto Sans CJK SC"
        "Noto Sans"
      ];
      serif = [
        "Noto Serif CJK SC"
        "Noto Serif"
      ];
      emoji = [ "Noto Color Emoji" ];
    };
  };
}
