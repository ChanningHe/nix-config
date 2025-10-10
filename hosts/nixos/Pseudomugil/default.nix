{
  #inputs,
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
      "hosts/common/optional/no-firewall.nix"
      "hosts/common/optional/zfs-mirror-boot.nix"
      "hosts/common/optional/ip-forward.nix"
      "hosts/common/optional/services/easytier.nix"
      "hosts/common/optional/services/tailscale.nix"
      "hosts/common/optional/services/openssh-init.nix"
      "hosts/common/optional/services/komodo-periphery.nix"
    ])
  ];

  #
  # ========== Host Specification ==========
  #

  hostSpec = {
    hostName = "Pseudomugil";
    scaling = lib.mkForce "1";
    # loadUserAgeKey = true;
  };

  #
  # ========== Host Network ==========
  #
  networking = {
    # !!![FIXME]!!!
    hostId = "e874e2fb";
    networkmanager.enable = false;
    enableIPv6 = false;
    useDHCP = false;
    dhcpcd.enable = false;
    #nameservers = hostNetwork.dns;
    nameservers = [ "1.1.1.1" ];
    extraHosts = ''
      10.1.10.8 git.homielab.cc
    '';
  };

  services.resolved.enable = false;

  # systemd-networkd
  systemd.network = {
    enable = true;
    networks = {
      "10-wired" = {
        # [FIXME]
        matchConfig.Name = "enp197s0f1np1";
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

  #SB
  systemd.network.networks."10-enp193s0" = {
    matchConfig.Name = "enp193s0";
    networkConfig = {
      DHCP = "ipv4";
      IPv6AcceptRA = true;
    };
    dhcpV4Config = {
      RouteMetric = 2048;
    };
    # v6 的路由优先级也可以单独设
    ipv6AcceptRAConfig = {
      # 保留 RA 的默认路由但降低优先级（可选）
      RouteMetric = 2048;
      # 若你根本不想从 RA 装默认路由，则：UseGateway = false;
    };
  };

  boot.initrd = {
    systemd.enable = true;
  };

  boot.kernelParams = [
    "console=ttyS0,115200"
    "console=tty1"
    "amd_iommu=on"
    "amd_pstate=passive"
    "iommu=pt"
    "zfs.zfs_arc_max=4294967296"
    "pcie_aspm=off"
  ];

  # https://wiki.nixos.org/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "25.05";
}
