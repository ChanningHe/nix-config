{
  pkgs,
  ...
}:
{
  programs.neovim = {
    enable = true;
    #defaultEditor = true;
    vimAlias = true;
    viAlias = true;
    # Adopt the 26.05 defaults: lua-based config needs no ruby/python providers
    withRuby = false;
    withPython3 = false;
  };

  home.packages = with pkgs; [
    tree-sitter
    fd
    fzf
    ripgrep # Required for Telescope live_grep
    lazygit # Git integration
    nodejs # Required for many LSP servers
  ];

  # dotfiles = {
  #   components = [
  #     "nvim"
  #   ];
  # };
}
