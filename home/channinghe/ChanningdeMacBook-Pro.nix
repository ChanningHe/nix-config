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
    # SSH Agent with auto-loading
    common/optional/darwin/ssh-agent.nix

    # FIXME(starter): add or remove any optional config directories or files here
    # common/optional/browsers
    # common/optional/desktops
    # common/optional/comms
    # common/optional/media
    common/optional/neovim.nix

    # uncommit to auto add ssh-private-key && age user key
    # common/optional/sops.nix
  ];

  programs.zsh.shellAliases = {
    "2c" = "cd /Volumes/Codes/";
  };

  # SSH Clients Configuration
  # Enable specific SSH hosts from nix-secrets
  sshClients.enableAll = true;

  # Nix Remote Builders Configuration
  nix = {
    distributedBuilds = true;
    buildMachines = [
      {
        hostName = "Poecilia";
        systems = [ "x86_64-linux" ];
        sshUser = "channinghe";
        maxJobs = 4;
        speedFactor = 2;
        supportedFeatures = [
          "nixos-test"
          "benchmark"
          "big-parallel"
          "kvm"
        ];
      }
      {
        hostName = "nixos-rl";
        systems = [ "x86_64-linux" ];
        sshUser = "channinghe";
        protocol = "ssh-ng";
        maxJobs = 8;
        speedFactor = 8;
        supportedFeatures = [
          "nixos-test"
          "benchmark"
          "big-parallel"
          "kvm"
        ];
      }
    ];
  };
}
