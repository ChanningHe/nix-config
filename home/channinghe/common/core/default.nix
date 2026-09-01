{
  config,
  lib,
  pkgs,
  hostSpec,
  ...
}:
let
  platform = if hostSpec.isDarwin then "darwin" else "nixos";
in
{
  imports = lib.flatten [
    (map lib.custom.relativeToRoot [
      "modules/common/host-spec.nix"
      "modules/home"
    ])
    # load the platform specific core configuration
    ./${platform}.nix

    # Add/edit as desired
    ./bash.nix
    ./direnv.nix
    ./fonts.nix
    ./git.nix
    #./kitty.nix
    ./ssh.nix
    ./zsh.nix
    ./neovim.nix
    ./yazi.nix
  ];

  inherit hostSpec;

  home = {
    username = lib.mkDefault config.hostSpec.username;
    homeDirectory = lib.mkDefault config.hostSpec.home;
    stateVersion = lib.mkDefault "25.11";
    sessionPath = [
      "$HOME/.local/bin"
    ];
    sessionVariables = {
      SHELL = "bash";
      SOPS_EDITOR = "nvim";
      EDITOR = "nvim";
      NH_FLAKE = "$HOME/nix-src/nix-config";
      # Allow ad-hoc `nix shell/build/run` to build unfree packages (needs --impure)
      NIXPKGS_ALLOW_UNFREE = 1;
      # Locale settings
      LANG = "en_US.UTF-8";
      LC_MESSAGES = "en_US.UTF-8";
      # Colorized ls commands
      CLICOLOR = 1;
      #LS_COLORS = "di=34:ln=35:so=32:pi=33:ex=31:bd=34;46:cd=34;43:su=30;41:sg=30;46:tw=30;42:ow=30;43";
      #LS_COLORS = "rs=0:di=38;5;141:ln=38;5;147:so=38;5;135:pi=38;5;135:ex=38;5;114:bd=38;5;160:cd=38;5;160:su=38;5;124:sg=38;5;124:tw=38;5;161:ow=38;5;161:fi=0:";
    };
  };

  # Cross-platform packages only
  # Platform-specific packages are defined in nixos.nix and darwin.nix
  home.packages = with pkgs; [
    curl
    fastfetch # system info
    #pre-commit # git hooks
    # p7zip # compression & encryption
    # unzip # zip extraction
    # unrar # rar extraction
    #brush # shell implemented in Rust
    sops
    age
    ssh-to-age
    tree
    jq
    ripgrep
    nh
    btop
    wget
    #vivid
    # dev tools
    gh
    devenv
    bun
    # lsp
    nil
    nixd
    # langs
    go
    gcc
    cargo
    #python3
  ];

  nix = {
    package = lib.mkDefault pkgs.nix;
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      warn-dirty = false;
    };
  };

  programs.home-manager.enable = true;
}
