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
    ./kitty.nix
    ./ssh.nix
    ./zed.nix
    ./zsh.nix
  ];

  inherit hostSpec;

  home = {
    username = lib.mkDefault config.hostSpec.username;
    homeDirectory = lib.mkDefault config.hostSpec.home;
    stateVersion = lib.mkDefault "25.05";
    sessionPath = [
      "$HOME/.local/bin"
    ];
    sessionVariables = {
      FLAKE = "$HOME/src/nix/nix-config";
      SHELL = "zsh";
    };
  };

  # Cross-platform packages only
  # Platform-specific packages are defined in nixos.nix and darwin.nix
  home.packages = with pkgs; [
    curl
    pfetch # system info
    pre-commit # git hooks
    p7zip # compression & encryption
    unzip # zip extraction
    unrar # rar extraction
    sops
    age
    ssh-to-age
    tree
    jq
    ripgrep
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
