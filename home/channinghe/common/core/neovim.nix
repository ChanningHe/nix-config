{
  pkgs,
  ...
}:
{
  # NOTE: programs.neovim is intentionally NOT used. Current home-manager
  # always generates ~/.config/nvim/init.lua (provider host-prog settings),
  # which clobbers the externally managed LazyVim config. The nvim config
  # is owned entirely by ~/.config/nvim; nix only provides the packages.
  home.packages = with pkgs; [
    neovim
    tree-sitter
    fd
    fzf
    ripgrep # Required for Telescope live_grep
    lazygit # Git integration
    nodejs # Required for many LSP servers
  ];

  home.shellAliases = {
    vim = "nvim";
    vi = "nvim";
  };
}
