{
  ...
}:
{
  # home.packages = with pkgs; [
  #   neovim
  # ];

  programs.neovim = {
    enable = true;
    #defaultEditor = true;
    vimAlias = true;
    viAlias = true;
  };

}
