# Core functionality for every nixos host
{
  inputs,
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

  # Database for aiding terminal-based programs
  environment.enableAllTerminfo = true;
  # Enable firmware with a license allowing redistribution
  hardware.enableRedistributableFirmware = true;

  # This should be handled by config.security.pam.sshAgentAuth.enable
  security.sudo.extraConfig = ''
    Defaults lecture = never # rollback results in sudo lectures after each reboot, it's somewhat useless anyway
    Defaults pwfeedback # password input feedback - makes typed password visible as asterisks
    Defaults timestamp_timeout=120 # only ask for password every 2h
    # Keep SSH_AUTH_SOCK so that pam_ssh_agent_auth.so can do its magic.
    Defaults env_keep+=SSH_AUTH_SOCK
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

  # Allow cursor/vscode to dynamically linked binaries built for other Linux distributions
  programs.nix-ld.enable = true;

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

  #
  # ========== Nix Registry & NixPath ==========
  #
  nix = {
    # This will add each flake input as a registry
    # To make nix3 commands consistent with your flake
    registry = lib.mapAttrs (_: value: { flake = value; }) inputs;

    # This will add your inputs to the system's legacy channels
    # Making legacy nix commands consistent as well, awesome!
    nixPath = lib.mapAttrsToList (key: value: "${key}=${value.to.path}") config.nix.registry;

    # Deduplicate and optimize nix store (NixOS-specific)
    settings.auto-optimise-store = true;
  };

  #
  # ========== Localization ==========
  #
  i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";
  time.timeZone = lib.mkDefault "Asia/Tokyo";
}
