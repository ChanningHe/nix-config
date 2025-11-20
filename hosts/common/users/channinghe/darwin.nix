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
}
