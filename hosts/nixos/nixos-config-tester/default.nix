# This is an example nixos hosts module.
# They will automatically be imported below.

{
  inputs,
  lib,
  config,
  ...
}:
let
  # 直接引用已经导入的 network_info
  hostNetwork = config.hostSpec.networkInfo.hosts.${config.hostSpec.hostName};
in
{
  imports = lib.flatten [
    #
    # ========== Hardware ==========
    #
    ./hardware-configuration.nix

    #
    # ========== Disk Layout ==========
    #
    #inputs.disko.nixosModules.disko
    # FIXME(starter): modify with the disko spec file you want to use.
    # (lib.custom.relativeToRoot "hosts/common/disks/btrfs-disk.nix")
    # # FIXME(starter): modify the options below to inform disko of the host's disk path and swap requirements.
    # # IMPORTANT: nix-config-starter assumes a single disk per host. If you require more disks, you
    # # must modify or create new dikso specs.
    # {
    #   _module.args = {
    #     disk = "/dev/nvme0n1";
    #     withSwap = true;
    #     swapSize = 16;
    #   };
    # }

    (map lib.custom.relativeToRoot [
      #
      # ========== Required Configs ==========
      #
      "hosts/common/core"

      #
      # ========== Non-Primary Users to Create ==========
      #
      # FIXME(starter): the primary user, defined in `nix-config/hosts/common/users`, is added by default, via
      # `hosts/common/core` above.
      # To create additional users, specify the path to their config file, as shown in the commented line below, and create/modify
      # the specified file as required. See `nix-config/hosts/common/users/exampleSecondUser` for more info.

      #"hosts/common/users/exampleSecondUser"

      #
      # ========== Optional Configs ==========
      #
      # FIXME(starter): add or remove any optional host-level configuration files the host will use
      # The following are for example sake only and are not necessarily required.
      "hosts/common/optional/services/openssh-init.nix" # allow remote SSH access
      "hosts/common/optional/no-firewall.nix"
      "hosts/common/optional/zfs-mirror-boot.nix"
      #"hosts/common/optional/audio.nix" # pipewire and cli controls
      # "hosts/common/optional/xfce.nix" # lightweight x-based window manager
    ])
  ];

  #
  # ========== Host Specification ==========
  #

  # FIXME(starter): declare any host-specific hostSpec options. Note that hostSpec options pertaining to
  # more than one host can be declared in `nix-config/hosts/common/core/` see the default.nix file there
  # for examples.
  hostSpec = {
    hostName = "nixos-config-tester";
  };

  # networking = {
  #   networkmanager.enable = true;
  #   enableIPv6 = false;
  # };

  #
  # ========== Host Network ==========
  #

  networking = {
    hostId = "69d98e5c";
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
        matchConfig.Name = "ens18";
        networkConfig = {
          Address = [
            "${hostNetwork.ip4}/24"
          ];
          Gateway = [
            "${hostNetwork.gateway4}"
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

  # hardware.graphics = {
  #   enable = true;
  # };
  # https://wiki.nixos.org/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "25.05";
}
