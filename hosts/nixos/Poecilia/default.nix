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
      "hosts/common/optional/system/no-firewall.nix"
      "hosts/common/optional/system/zfs-mirror-boot.nix"
      "hosts/common/optional/system/ip-forward.nix"
      "hosts/common/optional/services/node-exporter.nix"
      "hosts/common/optional/services/easytier.nix"
      "hosts/common/optional/services/attic.nix"
      "hosts/common/optional/services/zfs-zed-mail.nix"
      "hosts/common/optional/services/znapzend.nix"
      "hosts/common/optional/network-storage.nix"
      "hosts/common/optional/ups.nix"
    ])
  ];

  #
  # ========== Host Specification ==========
  #

  hostSpec = {
    hostName = "Poecilia";
    #scaling = lib.mkForce "1";
    # [FIXME] if you want to load your primary user age key in this host
    # loadUserAgeKey = true;
  };

  #
  # ========== Host Network ==========
  #
  networking = {
    hostId = "e4ae58db";
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
        #matchConfig.Name = "enp3s0";
        matchConfig.MACAddress = "c8:ff:bf:01:c1:c4";
        matchConfig.Type = "ether";
        networkConfig = {
          Address = [
            "${hostNetwork.ip4}/24"
            "${hostNetwork.ip6}/64"
          ];
          Gateway = [
            "${hostNetwork.gateway4}"
            "${hostNetwork.gateway6}"
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
  fileSystems."/mnt/rpool/ConfigData" = {
    device = "rpool/ConfigData";
    fsType = "zfs";
  };

  fileSystems."/mnt/rpool/container-root/docker" = {
    device = "rpool/container-root/docker";
    fsType = "zfs";
  };

  virtualisation.docker = {
    enable = lib.mkDefault true; # Default enable, can be overridden
  };

  virtualisation.docker.daemon.settings = {
    data-root = "/mnt/rpool/container-root/docker";
  };

  # ===== environment variables ===== #
  environment.variables = {
    DOCKER_DATA = "/mnt/rpool/ConfigData/DockerConfig/DOCKER_DATA";
  };

  # ===== Kernel config =====
  boot.kernelParams = [
    #"amd_iommu=on"
    #"amd_pstate=passive"
    "iommu=pt"
    "zfs.zfs_arc_max=4294967296"
    "pcie_aspm=off"
    "pcie_port_pm=off"
    "pcie_aspm.policy=performance"
  ];

  boot.kernel.sysctl = {
    "net.ipv4.ip_unprivileged_port_start" = 80;
    "net.ipv4.ip_nonlocal_bind" = 1;
    "net.bridge.bridge-nf-call-iptables" = 0;
  };

  # https://wiki.nixos.org/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "25.05";
}
