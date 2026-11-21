# bird2 with its config kept out of the repo, in the primary user's
# ~/.config/bird. /etc/bird/bird.conf is only an include of it; relative
# includes inside resolve against ~/.config/bird.
#   check:  bird -p -c ~/.config/bird/bird.conf
#   apply:  birdc configure   (the primary user is in the bird group)
# The directory is bind-mounted into the unit at start: edit files in place.
# After replacing the directory (or retargeting a symlink) run
# `systemctl restart bird`, or birdc configure keeps reading the old one.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.hostSpec) username home;
  confDir = "${home}/.config/bird";
in
{
  services.bird = {
    enable = true;
    package = pkgs.bird2;
    config = ''
      include "${confDir}/bird.conf";
    '';
    # The real config is outside the store: nothing to check or reload on deploy
    checkConfig = false;
    autoReload = false;
  };

  systemd.services.bird.serviceConfig = {
    # Largest process with a full table; killing it withdraws the prefixes
    OOMScoreAdjust = -900;
    # Upstream hides /home entirely; expose only the config dir, read-only
    ProtectHome = lib.mkForce "tmpfs";
    BindReadOnlyPaths = [ confDir ];
  };

  users.users.${username}.extraGroups = [ "bird" ];
}
