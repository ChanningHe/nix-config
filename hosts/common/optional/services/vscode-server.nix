{ config, lib, pkgs, inputs, ... }:
{
  imports = [
    inputs.vscode-server.nixosModules.default
  ];

  # Enable VS Code Server for remote development
  services.vscode-server = {
    enable = true;
    installPath = [
      "$HOME/.cursor-server"
    ];
  };

  # Ensure the auto-fix service is available for users
  # Users need to manually enable it with:
  # systemctl --user enable auto-fix-vscode-server.service
  # systemctl --user start auto-fix-vscode-server.service
}
