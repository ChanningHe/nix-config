# NOTE: This module is required for nixos-anywhere
{ config, ... }:
{
  # Set a temp password for use by minimal builds like installer and iso
  users.users.${config.hostSpec.username} = {
    isNormalUser = true;
    uid = 3000;
    #FIXME(starter): if desired, you can change the password that is used by the ISO below.

    # This is a hashed version of the plain-text password "nixos" for use in the ISO. Even though,
    # the password is known, we use `hashedPassword` here instead of `password` to mitigate
    # occurrences of the latter not being used during build.
    hashedPassword = "$y$j9T$3eYW3dFtYIxZeKhwc1Pnw.$on6nsn0dVob35N3BSrP6yglLEZ1jY1JzCKtwq.XC../";
    extraGroups = [ "wheel" ];
  };
  users.groups.${config.hostSpec.username} = {
    gid = 3000;
  };
}
