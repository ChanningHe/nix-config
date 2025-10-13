#NOTE(starter): Unlike the host-level host files that are structured as `nix-config/hosts/[platform]/[hostname]/default.nix`
# the corresponding home-level files are housed in each user's home-level config directory. This allows you to customize
# user-specific, home-manager configurations on a per user basis. The `home/common/optional/foo` configs, along with
# `home/common/core` allow you to import the specific home-manager configs you want for each host
{ ... }:
{
  imports = [
    #
    # ========== Required Configs ==========
    #
    common/core

    #
    # ========== Host-specific Optional Configs ==========
    #
    # FIXME(starter): add or remove any optional config directories or files here
    # common/optional/browsers
    # common/optional/desktops
    # common/optional/comms
    # common/optional/media

    # uncommit to auto add ssh-private-key && age user key
    # common/optional/sops.nix
  ];
  
  # ==== bash config for specific host ==== #
  programs.bash = {
    shellAliases = {
      nxsw = "sudo nixos-rebuild switch";
      "2dd" = "cd /mnt/rpool/ConfigData/DockerConfig/DOCKER_DATA";
   };
  };
}
