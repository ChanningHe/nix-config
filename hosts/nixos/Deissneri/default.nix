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

  # systemd-networkd. Match by MAC (stable across renames) when known,
  # otherwise fall back to the interface name. Both come from network.nix
  # and are back-filled by spawn.sh.
  systemd.network = {
    enable = true;
    networks = {
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

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

  # https://wiki.nixos.org/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "25.05";
}
