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
  };

  home.packages = with pkgs; [
    tree-sitter
    fd
    fzf
    ripgrep # Required for Telescope live_grep
    lazygit # Git integration
    nodejs # Required for many LSP servers
  ];

  dotfiles = {
    components = [
      "nvim"
    ];
  };
}
