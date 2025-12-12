# FIXME(starter): modify this file and the other .nix files in `nix-config/hosts/common/core/` to declare
# settings that will occur across all hosts

# IMPORTANT: This is used by NixOS and nix-darwin so options must exist in both!
{
  inputs,
  outputs,
  config,
  lib,
  pkgs,
  isDarwin,
  ...
}:
let
  platform = if isDarwin then "darwin" else "nixos";
  platformModules = "${platform}Modules";
in
{
  imports = lib.flatten [
    inputs.home-manager.${platformModules}.home-manager
    inputs.sops-nix.${platformModules}.sops

    (map lib.custom.relativeToRoot [
      "modules/common"
      "modules/hosts/common"
      "modules/hosts/${platform}"
      "hosts/common/core/${platform}.nix"
      "hosts/common/core/sops.nix" # Core because it's used for backups, mail
      "hosts/common/core/ssh.nix"
      #"hosts/common/core/services" # uncomment this line if you add any modules to services directory
      # --- My primary user ---
      "hosts/common/users/channinghe"
      "hosts/common/users/channinghe/${platform}.nix"
    ])
  ];

  #
  # ========== Core Host Specifications ==========
  #
  # FIXME(starter): modify the hostSpec options below to define values that are common across all hosts
  # such as the username and handle of the primary user (see also `nix-config/hosts/common/users/primary`)
  hostSpec = {
    username = "channinghe";
    handle = "channinghe";
    # FIXME(starter): modify the attribute sets hostSpec will inherit from your nix-secrets.
    # If you're not using nix-secrets then remove the following six lines below.
    inherit (inputs.nix-secrets)
      domain
      email
      userFullName
      networking
      networkInfo
      serviceInfo
      ;
  };

  networking.hostName = config.hostSpec.hostName;

  # System-wide packages, in case we log in as root
  # NOTE: Only cross-platform packages here. Platform-specific packages go to darwin.nix or nixos.nix
  environment.systemPackages = with pkgs; [
    openssh
    git
    curl
    nano
    nmap
    sops
    age
    ssh-to-age
    dnsutils
  ];
  # Force home-manager to use global packages
  home-manager.useGlobalPkgs = true;

  # If there is a conflict file that is backed up, use this extension
  home-manager.backupFileExtension = "bk";

  #
  # ========== Overlays ==========
  #
  nixpkgs = {
    overlays = [
      outputs.overlays.default
    ];
    config = {
      allowUnfree = true;
    };
  };

  #
  # ========== Nix Nix Nix ==========
  #
  nix = {
    # # This will add each flake input as a registry
    # # To make nix3 commands consistent with your flake
    # registry = lib.mapAttrs (_: value: { flake = value; }) inputs;

    # # This will add your inputs to the system's legacy channels
    # # Making legacy nix commands consistent as well, awesome!
    # nixPath = lib.mapAttrsToList (key: value: "${key}=${value.to.path}") config.nix.registry;

    # NOTE: registry and nixPath configuration moved to platform-specific files
    # (darwin.nix and nixos.nix) due to different handling between platforms

    settings =
      let
        # Office cache (local LAN buffer for cache.nixos.org)
        ncpsCache = config.hostSpec.serviceInfo.nixCacheInfo.ncps or { };
        ncpsCacheHost = ncpsCache.host or "";
        ncpsCachePubkey = ncpsCache.pubkey or "";
        hasNcpsCache = ncpsCacheHost != "" && ncpsCachePubkey != "";
      in
      {
        # See https://jackson.dev/post/nix-reasonable-defaults/
        connect-timeout = 5;
        log-lines = 25;
        min-free = 128000000; # 128MB
        max-free = 1000000000; # 1GB

        trusted-users = [
          "@wheel"
          "root"
          # For linux-builder
          "@admin"
          config.hostSpec.username
        ];
        # NOTE: auto-optimise-store moved to platform-specific files
        # (Darwin uses nix.optimise.automatic, NixOS uses nix.settings.auto-optimise-store)
        warn-dirty = false;

        #https://github.com/NixOS/nix/issues/11728#issuecomment-2725297584
        download-buffer-size = 524288000;

        allow-import-from-derivation = true;

        experimental-features = [
          "nix-command"
          "flakes"
        ];

        # Default cache configuration: office-cache (LAN buffer) -> cache.nixos.org
        substituters = lib.optional hasNcpsCache "https://${ncpsCacheHost}" ++ [
          "https://cache.nixos.org"
        ];

        trusted-public-keys = lib.optional hasNcpsCache "${ncpsCacheHost}:${ncpsCachePubkey}" ++ [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        ];
      };
  };
}
