# BGP border VM (AS218155). Network, firewall and data: optional/system/bgp-border.
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
    (lib.optional (builtins.pathExists ./facter.json) {
      facter.reportPath = ./facter.json;
    })

    #
    # ========== Disk Layout & Bootloader ==========
    #
    (lib.custom.bootDiskLayout inputs {
      layout = "ext4";
    })

    (map lib.custom.relativeToRoot [
      #
      # ========== Required Configs ==========
      #
      "hosts/common/core"

      #
      # ========== Optional Configs ==========
      #
      # No no-firewall.nix / ip-forward.nix: bgp-border owns firewall and forwarding
      "hosts/common/optional/system/qemu-guest.nix"
      "hosts/common/optional/system/low-mem.nix"
      "hosts/common/optional/system/bgp-border"
      "hosts/common/optional/services/bird.nix"
    ])
  ];

  #
  # ========== Host Specification ==========
  #
  hostSpec = {
    hostName = "marginatus";
    scaling = lib.mkForce "1";
  };

  networking = {
    hostId = "d3f76f5e";
    nameservers = hostNetwork.dns;
    # The edge NIC only lets the home networks out (bgp-border)
    timeServers = hostNetwork.ntp;
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # https://wiki.nixos.org/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "26.05";
}
