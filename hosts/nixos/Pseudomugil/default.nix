{
  inputs,
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
    # Declarative hardware detection via nixos-facter.
    # Skipped until then so the host still evaluates.
    # Defaults in hosts/common/core/facter.nix.
    (lib.optional (builtins.pathExists ./facter.json) { facter.reportPath = ./facter.json; })
    #inputs.hardware.nixosModules.common-cpu-amd
    #inputs.hardware.nixosModules.common-cpu-intel
    #inputs.hardware.nixosModules.common-gpu-nvidia
    #inputs.hardware.nixosModules.common-gpu-intel
    #inputs.hardware.nixosModules.common-pc-ssd

    #
    # ========== Disk Layout & Bootloader ==========
    #
    # Boot-disk layout + matching bootloader.
    (lib.custom.bootDiskLayout inputs {
      layout = "zfs-mirror"; # ext4 | btrfs | zfs | zfs-mirror
      disk = "/dev/disk/by-id/ata-INTEL_SSDSC2BB160G4_PHWL508000AD160MGN";
      disk2 = "/dev/disk/by-id/nvme-SAMSUNG_MZ9L4128HCHQ-00BH1_S774NF0X619395";
    })

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
      "hosts/common/optional/system/ip-forward.nix"
      "hosts/common/optional/system/ipmi.nix"
      "hosts/common/optional/services/ipmi-bmc-reset.nix"
      "hosts/common/optional/services/node-exporter.nix"
      #"hosts/common/optional/services/easytier.nix"
      "hosts/common/optional/services/wireguard.nix"
      "hosts/common/optional/services/tailscale.nix"
      "hosts/common/optional/services/komodo-periphery.nix"
      "hosts/common/optional/services/attic.nix"
      "hosts/common/optional/services/zfs-zed-mail.nix"
      "hosts/common/optional/network-storage.nix"
      "hosts/common/optional/system/nvidia-vgpu.nix"
      "hosts/common/optional/services/podman.nix"
      #"hosts/common/optional/services/incus.nix"
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
    #nameservers = hostNetwork.dns;
    nameservers = [ "1.1.1.1" ];
    extraHosts = ''
      10.1.10.8 git-local.homielab.cc
    '';
  };

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
        #matchConfig.Name = "enp196s0f1np1";
        # Type=ether is REQUIRED: vlan-mgmt/vlan10 inherit this same MAC, so a
        # bare MACAddress match also grabs them (10-wired sorts first), steals
        # them from their own *.network and leaves the bridges memberless ->
        # no-carrier -> systemd-networkd-wait-online times out.
        matchConfig.MACAddress = "b8:ce:f6:29:46:5d";
        matchConfig.Type = "ether";
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
  systemd.network.networks."10-softbank" = {
    #matchConfig.Name = "enp193s0";
    matchConfig.MACAddress = "00:e0:97:2a:1b:45";
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

  boot.kernelParams = [
    "amd_iommu=on"
    "amd_pstate=passive"
    # iommu=pt comes from the nvidia-vgpu module
    "zfs.zfs_arc_max=4294967296"
    "pcie_aspm=off"
  ];

  # https://wiki.nixos.org/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "25.05";
}
