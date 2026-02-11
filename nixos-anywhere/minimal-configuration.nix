{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = lib.flatten [
    (map lib.custom.relativeToRoot [
      "modules/common/host-spec.nix"
      "hosts/common/core/ssh.nix"
      "hosts/common/users/channinghe"
      "hosts/common/optional/minimal-user.nix"
    ])
  ];

  hostSpec = {
    isMinimal = lib.mkForce true;
    hostName = "installer";
    # FIXME(starter): Add your primary username or whatever user you want to use for installation
    username = "channinghe";
  };

  # NOTE: boot.loader configuration is provided by nixos-anywhere/boot/*.nix modules,
  # selected by the NIXOS_DISK_LAYOUT environment variable in flake.nix.
  #
  # Essential initrd modules so the installed system can boot even without
  # hardware-configuration.nix (which is generated later in Phase 2).
  # Covers QEMU/KVM (virtio + SATA), VMware, and common bare-metal controllers.
  boot.initrd = {
    availableKernelModules = [
      # Virtio (QEMU/KVM)
      "virtio_pci"
      "virtio_mmio"
      "virtio_blk"
      "virtio_scsi"
      "virtio_net"
      # SATA / AHCI
      "ahci"
      # SCSI
      "sd_mod"
      "sr_mod"
      # NVMe
      "nvme"
      # USB host controllers (for USB-boot scenarios)
      "xhci_pci"
      "ehci_pci"
      "uhci_hcd"
    ];
    kernelModules = [
      "virtio_balloon"
      "virtio_console"
      "virtio_rng"
    ];
    systemd.enable = true;
    systemd.emergencyAccess = true; # Don't need to enter password in emergency mode
  };
  boot.kernelParams = [
    "systemd.setenv=SYSTEMD_SULOGIN_FORCE=1"
    "systemd.show_status=true"
    #"systemd.log_level=debug"
    "systemd.log_target=console"
    "systemd.journald.forward_to_console=1"
    "nomodeset"
    "vga=normal"
    # Console output
    "console=ttyS0,115200"
    "console=tty1"
  ];

  environment.systemPackages = builtins.attrValues {
    inherit (pkgs)
      wget
      curl
      rsync
      git
      ;
  };

  networking = {
    networkmanager.enable = true;
  };

  # Root needs SSH keys + password for post-install provisioning (Phase 1→2).
  # nixos.nix normally handles this, but minimal-configuration.nix does not
  # import it (to avoid sops dependency). Mirror the relevant root config here.
  users.users.root = {
    openssh.authorizedKeys.keys =
      config.users.users.${config.hostSpec.username}.openssh.authorizedKeys.keys;
    hashedPassword = config.users.users.${config.hostSpec.username}.hashedPassword;
  };

  security.sudo.wheelNeedsPassword = false;

  services = {
    qemuGuest.enable = true;
    openssh = {
      enable = true;
      ports = [ 22 ];
      settings.PermitRootLogin = "yes";
      authorizedKeysFiles = lib.mkForce [ "/etc/ssh/authorized_keys.d/%u" ];
    };
  };

  nix = {
    # registry and nixPath shouldn't be required here because flakes but removal results in warning spam on build
    registry = lib.mapAttrs (_: value: { flake = value; }) inputs;
    nixPath = lib.mapAttrsToList (key: value: "${key}=${value.to.path}") config.nix.registry;

    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      warn-dirty = false;
    };
  };

  system.stateVersion = "25.05";
}
