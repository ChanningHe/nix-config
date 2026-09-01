# User config applicable only to darwin
{
  config,
  pkgs,
  ...
}:
{
  users.users.${config.hostSpec.username} = {
    home = "/Users/${config.hostSpec.username}";
    # Use zsh as default shell on Darwin
    # shell = pkgs.zsh;
  };

  # nix-darwin does not manage this pre-existing user's shell (no knownUsers);
  # register nix bash in /etc/shells so it can be adopted manually:
  #   chsh -s /run/current-system/sw/bin/bash
  environment.shells = [ pkgs.bashInteractive ];
  environment.systemPackages = [ pkgs.bashInteractive ];
}
