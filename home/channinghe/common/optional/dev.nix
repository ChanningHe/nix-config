# Development toolchain: editor, LSPs, dev environments, remote-editor servers.
{
  lib,
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
    gh
    devenv
    # lsp
    nil
    nixd
    # langs
    go
    gcc
    cargo
    python3
  ];

  home.shellAliases = {
    vim = "nvim";
    vi = "nvim";
  };

  home.sessionVariables = {
    EDITOR = "nvim";
    SOPS_EDITOR = "nvim";
  };

  programs.git.package = pkgs.gitFull;

  # For Zed Remote Server
  home.file.".zed_server" = lib.mkIf pkgs.stdenv.isLinux {
    source = "${pkgs.zed-editor.remote_server}/bin";
    # keeps the folder writable, but symlinks the binaries into it
    recursive = true;
  };
}
