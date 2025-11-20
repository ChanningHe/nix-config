# Darwin-specific home-manager configuration
# This file contains configurations that only work on macOS systems
{
  pkgs,
  ...
}:
{
  # Add Homebrew to PATH
  home.sessionPath = [ "/opt/homebrew/bin" ];

  # Darwin-specific packages (if needed)
  home.packages = with pkgs; [
    rustup
    nixpkgs-fmt
    # Add Darwin-specific packages here if needed
  ];
}
