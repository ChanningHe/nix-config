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
      "hosts/common/users/rl-man"

      #
      # ========== Optional Configs ==========
      "hosts/common/optional/system/no-firewall.nix"
      "hosts/common/optional/system/zfs-mirror-boot.nix"
      "hosts/common/optional/system/ip-forward.nix"
      "hosts/common/optional/system/ipmi.nix"
      "hosts/common/optional/services/easytier.nix"
      "hosts/common/optional/services/tailscale.nix"
      "hosts/common/optional/services/komodo-periphery.nix"
      "hosts/common/optional/services/attic.nix"
      "hosts/common/optional/services/zfs-zed-mail.nix"
      "hosts/common/optional/network-storage.nix"
      #"hosts/common/optional/services/proxmox-ve.nix"
      "hosts/common/optional/services/vscode-server.nix"
      "hosts/common/optional/services/podman.nix"
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
    hostId = "e874e2fb";
    networkmanager.enable = false;
    enableIPv6 = false;
    useDHCP = false;
    dhcpcd.enable = false;
    #nameservers = hostNetwork.dns;
    nameservers = [ "1.1.1.1" ];
    extraHosts = ''
      10.1.10.8 git-local.homielab.cc
    '';
  };

  services.resolved.enable = false;

  # systemd-networkd
  # systemd.network = {
  #   enable = true;
  #   networks = {
  #     "10-wired" = {
  #       # [FIXME]
  #       matchConfig.Name = "enp197s0f1np1";
  #       networkConfig = {
  #         Address = [
  #           "${hostNetwork.ip4}/24"
  #           #"${hostNetwork.ip6}/64"
  #         ];
  #         Gateway = [
  #           "${hostNetwork.gateway4}"
  #           #"${hostNetwork.gateway6}"
  #         ];
  #         DHCP = "no";
  #         IPv6AcceptRA = false;
  #       };
  #     };
  #   };
  # };
  systemd.network = {
    enable = true;
    netdevs = {
      # Bridges
      # "br0" = {
      #   netdevConfig = {
      #     Name = "br0";
      #     Kind = "bridge";
      #   };
      #   bridgeConfig.STP = true;  # Enable STP
      # };
      "20-vlan-mgmt" = {
        netdevConfig = {
          Kind = "vlan";
          Name = "vlan-mgmt";
        };
        vlanConfig.Id = 250;
      };
      "20-br-mgmt" = {
        netdevConfig = {
          Kind = "bridge";
          Name = "br-mgmt";
        };
        bridgeConfig.STP = false;
      };
      "30-vlan10" = {
        netdevConfig = {
          Kind = "vlan";
          Name = "vlan10";
        };
        vlanConfig.Id = 10;
      };
      "30-vmbr10" = {
        netdevConfig = {
          Kind = "bridge";
          Name = "vmbr10";
        };
        bridgeConfig.STP = false;
      };
    };
    networks = {
      "10-wired" = {
        matchConfig.Name = "enp196s0f1np1";
        networkConfig = {
          VLAN = [
            "vlan-mgmt"
            "vlan10"
          ];
          DHCP = "no";
          IPv6AcceptRA = false;
        };
      };

      "20-vlan-mgmt" = {
        matchConfig.Name = "vlan-mgmt";
        networkConfig = {
          Bridge = "br-mgmt";
          DHCP = "no";
          IPv6AcceptRA = false;
        };
      };

      "20-br-mgmt" = {
        matchConfig.Name = "br-mgmt";
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

      "30-vlan10" = {
        matchConfig.Name = "vlan10";
        networkConfig = {
          Bridge = "vmbr10";
          DHCP = "no";
          IPv6AcceptRA = false;
        };
      };

      "30-vmbr10" = {
        matchConfig.Name = "vmbr10";
        networkConfig = {
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
