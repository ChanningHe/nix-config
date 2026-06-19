{
  lib,
  config,
  ...
}:
let
  hostNetwork = config.hostSpec.networkInfo.hosts.${config.hostSpec.hostName};
in
{
  imports = lib.flatten [
    #
    # ========== Hardware ==========
    #
    ./hardware-configuration.nix
    #inputs.hardware.nixosModules.common-cpu-amd
    #inputs.hardware.nixosModules.common-cpu-intel
    #inputs.hardware.nixosModules.common-gpu-nvidia
    #inputs.hardware.nixosModules.common-gpu-intel
    #inputs.hardware.nixosModules.common-pc-ssd

    #
    # ========== Disk Layout ==========
    #
    #inputs.disko.nixosModules.disko

    #
    # ========== Misc Inputs ==========
    #

    (map lib.custom.relativeToRoot [
      #
      # ========== Required Configs ==========
      #
      "hosts/common/core"

      #
      # ========== Non-Primary Users to Create ==========
      #
      "hosts/common/users/rl-man"
      #
      # ========== Optional Configs ==========
      #
      "hosts/common/optional/system/systemd-boot.nix"
      "hosts/common/optional/system/no-firewall.nix"
      "hosts/common/optional/system/ip-forward.nix"
      "hosts/common/optional/services/attic.nix"
      "hosts/common/optional/network-storage.nix"
      # rdma config
      "hosts/common/optional/system/rdma/nfs-client.nix"
      "hosts/common/optional/system/rdma/vf-promisc.nix"
      "hosts/common/optional/system/rdma/roce.nix"
      #"hosts/common/optional/services/komodo-periphery.nix"
      #"hosts/common/optional/services/podman.nix"
    ])
  ];

  #
  # ========== Host Specification ==========
  #

  hostSpec = {
    hostName = "Annulatus";
    scaling = lib.mkForce "1";
    # loadUserAgeKey = true;
  };

  #
  # ========== Host Network ==========
  #
  networking = {
    hostId = "15b9f89f";
    networkmanager.enable = false;
    enableIPv6 = false;
    useDHCP = false;
    dhcpcd.enable = false;
    nameservers = hostNetwork.dns;
  };

  services.resolved.enable = false;

  # systemd-networkd
  systemd.network = {
    enable = true;
    networks = {
      "10-wired" = {
        matchConfig.Name = "enp1s0";
        networkConfig = {
          Address = [
            "${hostNetwork.ip4}/24"
            #"${hostNetwork.ip6}/64"
          ];
          Gateway = [
            "${hostNetwork.gateway4}"
            #"${hostNetwork.gateway6}"
          ];
          DHCP = "no";
          IPv6AcceptRA = false;
        };
      };
    };
  };

  boot.initrd = {
    systemd.enable = true;
  };

  # https://wiki.nixos.org/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "25.05";
}
