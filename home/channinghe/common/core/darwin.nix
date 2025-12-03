# Darwin-specific home-manager configuration
# This file contains configurations that only work on macOS systems
{
  pkgs,
  ...
}:
{
  # Add Homebrew to PATH
  home.sessionPath = [ "/opt/homebrew/bin" ];

  # Darwin-specific environment variables
  home.sessionVariables = {
    SOPS_AGE_KEY_FILE = "~/.config/sops/age/keys.txt";
    SOPS_EDITOR = "nano";
    EDITOR = "/opt/homebrew/bin/nano";
    NH_FLAKE = "$HOME/nix-src/nix-config";
  };

  # Darwin-specific packages (if needed)
  home.packages = with pkgs; [
    #rustup
    #nixpkgs-fmt
    # Add Darwin-specific packages here if needed
  ];
}
