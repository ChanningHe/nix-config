{
  lib,
  pkgs,
  ...
}:
{
  # The agent itself comes from home-manager (services.ssh-agent), which also
  # covers standalone homeConfigurations; a system one would just be shadowed.
  programs.ssh = lib.optionalAttrs pkgs.stdenv.isLinux {
    enableAskPassword = true;
  };
}
