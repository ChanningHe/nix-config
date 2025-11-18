# Core functionality for every nix-darwin host
# NOTE(starter): Declare any darwin-specific, core configurations here.
{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:
{
  # Set the host platform for Darwin
  nixpkgs.hostPlatform = lib.mkDefault "aarch64-darwin";

  # Darwin-specific system settings
  system.configurationRevision = null;

  # Enable sudo authentication via Touch ID
  security.pam.services.sudo_local.touchIdAuth = true;

  # ========== Nix Registry & NixPath ==========
  #
  # NOTE: On Darwin, we need to use mkForce to override nix-darwin's defaults
  nix = {
    # This will add each flake input as a registry
    # To make nix3 commands consistent with your flake
    registry = lib.mkForce (lib.mapAttrs (_: value: { flake = value; }) inputs);

    # This will add your inputs to the system's legacy channels
    # Making legacy nix commands consistent as well, awesome!
    nixPath = lib.mkForce (lib.mapAttrsToList (key: value: "${key}=${value.to.path}") config.nix.registry);

    # Deduplicate and optimize nix store (Darwin-specific)
    # NOTE: Darwin uses nix.optimise.automatic instead of settings.auto-optimise-store
    # because auto-optimise-store is known to corrupt the Nix Store on Darwin
    optimise.automatic = true;
  };
}
