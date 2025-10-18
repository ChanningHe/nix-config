# Service user configuration for running applications
# This is a minimal, security-focused user for service isolation

{
  inputs,
  pkgs,
  config,
  lib,
  ...
}:
{
  # Create the rl group first
  users.groups.rl = {
    gid = 5000;
    members = [
      "channinghe"
      "rl-man"
    ];
  };

  # Create the rl-man regular user for running applications
  users.users.rl-man = {
    uid = 5000;
    group = "rl";
    isNormalUser = true;  # Regular user, not system user
    shell = pkgs.bash;
    home = "/home/rl-man";
    createHome = true;
    description = "Regular user for running applications with minimal packages";
    
    # Minimal system groups - only what's absolutely necessary
    extraGroups = [ ];
    
    # No password login initially - can be changed later if needed
    hashedPassword = "!";
  };

  # Create minimal home directory structure
  systemd.tmpfiles.rules = [
    "d /home/rl-man 0750 rl-man rl -"
    "d /home/rl-man/.local 0750 rl-man rl -"
    "d /home/rl-man/.local/bin 0750 rl-man rl -"
  ];

  # Define minimal system packages for this user only if home-manager is available
} // lib.optionalAttrs (inputs ? "home-manager") {
  home-manager = {
    extraSpecialArgs = {
      inherit pkgs inputs;
      hostSpec = config.hostSpec;
    };
    users.rl-man.imports = lib.flatten [
      (
        { config, ... }:
        import (lib.custom.relativeToRoot "home/rl-man/${config.hostSpec.hostName}.nix") {
          inherit
            pkgs
            inputs
            config
            lib
            ;
          # Create a regular user hostSpec with minimal packages
          hostSpec = config.hostSpec // {
            username = "rl-man";
            home = "/home/rl-man";
            # Regular user - isMinimal is only for system installers
          };
        }
      )
    ];
  };
}
