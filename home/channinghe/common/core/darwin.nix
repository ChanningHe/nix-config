# FIXME(starter): the declarations here will ONLY be applied to Darwin-based machines.
# Core home functionality that will only work on Darwin
{ config, ... }:
{
  home.sessionPath = [ "/opt/homebrew/bin" ];

  home = {
    username = config.hostSpec.username;
    homeDirectory = config.hostSpec.home;
  };
}
