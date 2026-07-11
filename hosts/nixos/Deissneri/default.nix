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
    (lib.optional (builtins.pathExists ./facter.json) {
      imports = [ inputs.nixos-facter-modules.nixosModules.facter ];
      facter.reportPath = ./facter.json;
    })
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
      layout = "zfs"; # ext4 | btrfs | zfs | zfs-mirror
      disk = "/dev/disk/by-id/nvme-EO000375KWJUC_PHKE203600DZ375AGN";
    })

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
      "hosts/common/optional/system/ip-forward.nix"
      "hosts/common/optional/services/attic.nix"
      "hosts/common/optional/system/ipmi.nix"
      "hosts/common/optional/services/node-exporter.nix"
    ])
  ];

  #
  # ========== Host Specification ==========
  #

  hostSpec = {
    hostName = "Deissneri";
    scaling = lib.mkForce "1";
    # loadUserAgeKey = true;
  };

  #
  # ========== Host Network ==========
  #
  networking = {
    hostId = "02ca03a2";
    networkmanager.enable = false;
    enableIPv6 = false;
    useDHCP = false;
    dhcpcd.enable = false;
    nameservers = hostNetwork.dns;
  };

  services.resolved.enable = false;

  # systemd-networkd.
  #
  # Physical NIC is on a switch trunk port:
  #   - untagged  VLAN 110  -> management, host IP lives here
  #   - tagged    VLAN 4020 -> Incus guest isolation segment
  #   - tagged    VLAN 4050 -> Incus guest isolation segment
  #
  # Physical NIC is enslaved to br-mgmt directly (untagged traffic falls
  # into the bridge), and tagged VLANs go through vlan netdevs into their
  # own bridges so Incus VMs / Podman macvlan can attach by bridge name.
  #
  # NIC is matched by MAC (stable across renames) when known, otherwise by
  # interface name. Both come from network.nix and are back-filled by
  # spawn.sh.
  systemd.network = {
    enable = true;

    netdevs = {
      # ---- Bridges (one per usable segment) ----
      "20-br-mgmt" = {
        netdevConfig = {
          Kind = "bridge";
          Name = "br-mgmt";
        };
        bridgeConfig.STP = false;
      };
      "20-br-g4020" = {
        netdevConfig = {
          Kind = "bridge";
          Name = "br-g4020";
        };
        bridgeConfig.STP = false;
      };
      "20-br-g4050" = {
        netdevConfig = {
          Kind = "bridge";
          Name = "br-g4050";
        };
        bridgeConfig.STP = false;
      };

      # ---- Tagged VLAN sub-interfaces on the physical NIC ----
      "30-vlan4020" = {
        netdevConfig = {
          Kind = "vlan";
          Name = "vlan4020";
        };
        vlanConfig.Id = 4020;
      };
      "30-vlan4050" = {
        netdevConfig = {
          Kind = "vlan";
          Name = "vlan4050";
        };
        vlanConfig.Id = 4050;
      };
    };

    networks = {
      # Physical NIC:
      #   - untagged (VLAN 110) falls directly into br-mgmt
      #   - tagged 4020 / 4050 are lifted into their vlan netdevs
      #
      # Type=ether is REQUIRED: vlan4020/vlan4050 inherit this same MAC,
      # so a bare MACAddress match would also grab them (10-wired sorts
      # first), steal them from their own *.network and leave the vlan
      # bridges memberless -> no-carrier -> networkd-wait-online timeout.
      "10-wired" = {
        matchConfig =
          if (hostNetwork.mac or null) != null then
            {
              MACAddress = hostNetwork.mac;
              Type = "ether";
            }
          else
            { Name = hostNetwork.interface or "eth0"; };
        networkConfig = {
          Bridge = "br-mgmt";
          VLAN = [
            "vlan4020"
            "vlan4050"
          ];
          LinkLocalAddressing = "no";
          IPv6AcceptRA = false;
        };
      };

      # Management bridge: host IP lives here.
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

      # VLAN 4020 -> guest isolation bridge (host owns no IP here).
      "30-vlan4020" = {
        matchConfig.Name = "vlan4020";
        networkConfig = {
          Bridge = "br-g4020";
          LinkLocalAddressing = "no";
          IPv6AcceptRA = false;
        };
      };
      "20-br-g4020" = {
        matchConfig.Name = "br-g4020";
        # Keep the bridge UP even before any guest attaches, and don't
        # block boot on it.
        networkConfig = {
          DHCP = "no";
          LinkLocalAddressing = "no";
          IPv6AcceptRA = false;
          ConfigureWithoutCarrier = true;
        };
        linkConfig.RequiredForOnline = "no";
      };

      # VLAN 4050 -> guest isolation bridge.
      "30-vlan4050" = {
        matchConfig.Name = "vlan4050";
        networkConfig = {
          Bridge = "br-g4050";
          LinkLocalAddressing = "no";
          IPv6AcceptRA = false;
        };
      };
      "20-br-g4050" = {
        matchConfig.Name = "br-g4050";
        networkConfig = {
          DHCP = "no";
          LinkLocalAddressing = "no";
          IPv6AcceptRA = false;
          ConfigureWithoutCarrier = true;
        };
        linkConfig.RequiredForOnline = "no";
      };
    };
  };

  boot = {
    initrd.systemd.enable = true;
    #blacklistedKernelModules = [ "xgene-hwmon" ];
  };

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

  # https://wiki.nixos.org/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "25.05";
}
