#FIXME: Move attrs that will only work on linux to nixos.nix
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
    ./${platform}.nix

    # Service users don't need complex bash/ssh configurations
    # Keep it minimal - only essential functionality
  ];

  inherit hostSpec;

  # Disable ssh-agent for service user - not needed for application services
  services.ssh-agent.enable = false;

  home = {
    username = lib.mkDefault config.hostSpec.username;
    homeDirectory = lib.mkDefault config.hostSpec.home;
    stateVersion = lib.mkDefault "24.11";
    sessionPath = [
      "$HOME/.local/bin"
    ];
    sessionVariables = {
      # Minimal environment for service user
      SHELL = "bash";
    };
  };

  # Minimal packages for service user - only absolute essentials
  home.packages = builtins.attrValues {
    inherit (pkgs)
      # Network tools for basic service communication
      #curl
      # Archive handling for service deployments
      nano
      ;
  };

  # Minimal nix configuration for service user
  nix = {
    package = lib.mkDefault pkgs.nix;
    settings = {
      warn-dirty = false;
    };
  };

  programs.home-manager.enable = true;

  # Disable systemd user service management for service user
  # Service users typically don't need home-manager to manage systemd services
  systemd.user.startServices = "ignore-dependencies";
}
