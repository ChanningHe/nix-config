# Core functionality for every nixos host
{
  config,
  lib,
  pkgs,
  ...
}:
{
  # Linux-specific system packages
  environment.systemPackages = with pkgs; [
    ethtool # Ethernet tools
    pciutils # PCI device utilities (lspci)
    usbutils # USB device utilities (lsusb)
  ];

  # Networking is static systemd-networkd per host; nothing else manages links or DNS.
  # Plain values, not mkDefault: nixpkgs itself mkDefaults resolved (networkd) and
  # networkmanager (gnome) to true. A host opting back in needs lib.mkForce.
  networking = {
    networkmanager.enable = false;
    useDHCP = false;
    dhcpcd.enable = false;
  };
  services.resolved.enable = false;

  # systemd stage 1 (already the 26.05 default; pinned so it can't silently flip)
  boot.initrd.systemd.enable = lib.mkDefault true;

  # Database for aiding terminal-based programs
  environment.enableAllTerminfo = true;
  # Redistributable firmware (~850MB closure). Also the default for
  # hardware.cpu.{intel,amd}.updateMicrocode, so keep it on for bare metal;
  # VMs turn it off in optional/system/qemu-guest.nix.
  hardware.enableRedistributableFirmware = lib.mkDefault true;

  # env_keep+=SSH_AUTH_SOCK is added by the pam rssh module (services/yubikey.nix)
  security.sudo.extraConfig = ''
    Defaults lecture = never # rollback results in sudo lectures after each reboot, it's somewhat useless anyway
    Defaults pwfeedback # password input feedback - makes typed password visible as asterisks
    Defaults timestamp_timeout=30
  '';

  # Console output
  boot.kernelParams = [
    "console=ttyS0,115200"
    "console=tty1"
  ];

  # boot.extraModprobeConfig = ''
  # # example settings
  # options yourmodulename optionA=valueA optionB=valueB # syntax
  # options thinkpad_acpi  fan_control=1                 # example #1 kernel module parameter
  # options usbcore        blinkenlights=1               # example #2 kernel module parameter
  # '';

  boot.kernelModules = [
    "rpcrdma"
  ];

  #
  # ========== Nix Helper ==========
  #
  # Provide better build output and garbage collection
  programs.nh = {
    enable = true;
    clean.enable = true;
    clean.extraArgs = "--keep-since 20d --keep 20";
    flake = "${config.hostSpec.home}/nix-config";
  };

  # Registry/NIX_PATH: nixpkgs.flake.setFlakeRegistry/setNixPath (default on with
  # nixosSystem) pin only `nixpkgs`. Pinning every input would drag all their
  # sources (other nixpkgs copies, hermes-agent, ...) into the system closure.

  #
  # ========== Localization ==========
  #
  i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";
  time.timeZone = lib.mkDefault "Asia/Tokyo";
}
