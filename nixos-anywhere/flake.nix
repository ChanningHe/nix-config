{
  description = "Minimal NixOS configuration for bootstrapping systems (env-var driven)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    disko.url = "github:nix-community/disko"; # Declarative partitioning and formatting
  };

  outputs =
    {
      self,
      nixpkgs,
      ...
    }@inputs:
    let
      inherit (self) outputs;

      minimalSpecialArgs = {
        inherit inputs outputs;
        lib = nixpkgs.lib.extend (self: super: { custom = import ../lib { inherit (nixpkgs) lib; }; });
      };

      # ===== Environment Variables (requires --impure) =====
      # In pure mode (nix flake check): builtins.getEnv returns "" → nixosConfigurations = {}
      # In impure mode (provision script): builtins.getEnv returns actual values → config is generated
      hostname = builtins.getEnv "NIXOS_HOSTNAME"; # e.g. "Poecilia"
      diskLayout =
        let
          v = builtins.getEnv "NIXOS_DISK_LAYOUT";
        in
        if v == "" then "ext4" else v; # ext4|btrfs|zfs|zfs-mirror
      disk =
        let
          v = builtins.getEnv "NIXOS_DISK";
        in
        if v == "" then "/dev/vda" else v; # primary disk device
      disk2 = builtins.getEnv "NIXOS_DISK2"; # secondary disk (zfs-mirror only)

      # ===== Disk Layout → Config Mapping =====
      diskSpecs = {
        ext4 = {
          path = ../hosts/common/disks/ext4-disk.nix;
          args = {
            inherit disk;
          };
        };
        btrfs = {
          path = ../hosts/common/disks/btrfs-disk.nix;
          args = {
            inherit disk;
            withSwap = false;
            swapSize = "0";
          };
        };
        zfs = {
          path = ../hosts/common/disks/zfs-disk.nix;
          args = {
            inherit disk;
          };
        };
        zfs-mirror = {
          path = ../hosts/common/disks/zfs-mirror-disk.nix;
          args = {
            primaryDisk = disk;
            secondaryDisk = disk2;
          };
        };
      };

      bootModules = {
        ext4 = ../hosts/common/optional/system/systemd-boot.nix;
        btrfs = ../hosts/common/optional/system/systemd-boot.nix;
        zfs = ./boot/zfs-single-boot.nix;
        zfs-mirror = ./boot/zfs-mirror-boot.nix;
      };

      spec = diskSpecs.${diskLayout};
      boot = bootModules.${diskLayout};

      # hardware-configuration.nix is optional for initial install.
      # It will be generated after nixos-anywhere installs and reboots the target.
      hwConfigPath = ../hosts/nixos/${hostname}/hardware-configuration.nix;
      hasHwConfig = hostname != "" && builtins.pathExists hwConfigPath;
    in
    {
      # When hostname is empty (pure mode), nixosConfigurations is an empty set.
      # When hostname is set via env var (impure mode), the target config is generated.
      #
      # Usage from provision-nixos.sh:
      #   export NIXOS_HOSTNAME="myhost" NIXOS_DISK_LAYOUT="zfs-mirror" \
      #          NIXOS_DISK="/dev/disk/by-id/nvme-A" NIXOS_DISK2="/dev/disk/by-id/nvme-B"
      #   nix build --impure ./nixos-anywhere#nixosConfigurations.myhost.config.system.build.diskoScript
      #   nix build --impure ./nixos-anywhere#nixosConfigurations.myhost.config.system.build.toplevel
      nixosConfigurations = nixpkgs.lib.optionalAttrs (hostname != "") {
        ${hostname} = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = minimalSpecialArgs;
          modules = [
            inputs.disko.nixosModules.disko
            spec.path
            { _module.args = spec.args; }
            boot
            ./minimal-configuration.nix
            { networking.hostName = hostname; }
          ]
          ++ nixpkgs.lib.optional hasHwConfig hwConfigPath;
        };
      };
    };
}
