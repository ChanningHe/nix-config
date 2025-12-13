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

      #
      # ========== Optional Configs ==========
      #
      "hosts/common/optional/no-firewall.nix"
      "hosts/common/optional/zfs-boot.nix"
      "hosts/common/optional/services/openssh.nix"
      "hosts/common/optional/services/attic.nix"
      #"hosts/common/optional/services/znapzend.nix"
      #"hosts/common/optional/network-storage.nix"
    ])
  ];

  #
  # ========== Host Specification ==========
  #

  hostSpec = {
    hostName = "Macrouridae";
    #scaling = lib.mkForce "1";
    # [FIXME] if you want to load your primary user age key in this host
    # loadUserAgeKey = true;
  };

  #
  # ========== Host Network ==========
  #
  networking = {
    hostId = "6799b07f";
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
        matchConfig.Name = "enp3s0";
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

  #
  # ====== Filesystem ======
  #

  # ===== environment variables ===== #

  # ===== Kernel config =====
  boot.kernelParams = [
    #"amd_iommu=on"
    #"amd_pstate=passive"
    "iommu=pt"
    "intel_iommu=on"
    "zfs.zfs_arc_max=1073741824"
  ];

  # https://wiki.nixos.org/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "25.05";
}
