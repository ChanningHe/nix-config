# Standalone home-manager configuration for non-NixOS Linux hosts.
# Reuses common/core modules (zsh, git, neovim, ssh, etc.)
# with Linux-specific defaults (ssh-agent, systemd).
#
# Deploy: home-manager switch --flake .#channinghe@standalone-linux
{ ... }:
{
  imports = [
    common/core
  ];

  home.sessionVariables = {
    SOPS_AGE_KEY_FILE = "$HOME/.config/sops/age/keys.txt";
    EDITOR = "nvim";
    NH_FLAKE = "$HOME/nix-src/nix-config";
  };
}
