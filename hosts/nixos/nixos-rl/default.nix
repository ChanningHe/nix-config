{
  lib,
  config,
  modulesPath,
  ...
}:
let
  hostNetwork = config.hostSpec.networkInfo.hosts.${config.hostSpec.hostName};
in
{
  imports = lib.flatten [
    # import for nixos in lxc container
    "${modulesPath}/virtualisation/lxc-container.nix"
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
      "hosts/common/optional/system/ip-forward.nix"
      "hosts/common/optional/services/attic.nix"
      "hosts/common/optional/services/komodo-periphery.nix"
      "hosts/common/optional/services/docker.nix"
    ])
  ];

  #
  # ========== Host Specification ==========
  #

  hostSpec = {
    hostName = "nixos-rl";
    scaling = lib.mkForce "1";
    # loadUserAgeKey = true;
  };

  #
  # ========== Host Network ==========
  #
  networking = {
    # !!![FIXME]!!!
    hostId = "4083120b";
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
        matchConfig.Name = "eth0";
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
          IPv6AcceptRA = true;
        };
      };
    };
  };

  systemd.suppressedSystemUnits = [
    "dev-mqueue.mount"
    "sys-kernel-debug.mount"
    "sys-fs-fuse-connections.mount"
  ];

  environment.shellAliases = {
    nxsw = "nixos-rebuild switch";
    todd = "cd /mnt/Kiwi/VM/SCALE4stor/DockerConfig/nixos-rl/DOCKER_DATA/";
    "2dd" = "cd /mnt/Kiwi/VM/SCALE4stor/DockerConfig/nixos-rl/DOCKER_DATA/";
  };

  environment.variables = {
    DOCKER_DATA = "/mnt/Kiwi/VM/SCALE4stor/DockerConfig/nixos-rl/DOCKER_DATA";
  };

  # boot.initrd = {
  #   systemd.enable = true;
  # };

  # Disable sandboxing for running nixos in containers
  # https://nixos.wiki/wiki/Proxmox_Linux_Container
  #nix.settings.sandbox = false;
  #security.apparmor.enable = false;

  # FIXME(workaround): runc 1.2.7+ (CVE-2025-52881 fix) breaks Docker inside
  # unprivileged Proxmox LXC due to AppArmor path mismatch on detached procfs.
  # Pin runc to 1.2.6 until Proxmox host is updated to PVE 8.4.16+ (lxc-pve 6.0.5-2).
  # Upstream: https://github.com/opencontainers/runc/issues/4972
  # Permanent fix: add `lxc.apparmor.profile: unconfined` to /etc/pve/lxc/<CTID>.conf
  nixpkgs.overlays = [
    (_: prev: {
      # Docker bundles its own runc (docker-runc), built with pinned runcRev/runcHash
      # inside the docker package — overriding standalone `runc` has no effect.
      docker = prev.docker.override {
        runcRev = "v1.2.6";
        runcHash = "sha256-XMN+YKdQOQeOLLwvdrC6Si2iAIyyHD5RgZbrOHrQE/g=";
      };
    })
  ];

  # https://wiki.nixos.org/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "25.05";
}
