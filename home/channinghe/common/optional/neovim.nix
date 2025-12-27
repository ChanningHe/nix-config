{
  pkgs,
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

  home.packages = with pkgs; [
    tree-sitter
    fd
    fzf
  ];
}
