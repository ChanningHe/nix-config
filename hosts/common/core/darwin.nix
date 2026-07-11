# Core functionality for every nix-darwin host
# NOTE(starter): Declare any darwin-specific, core configurations here.
{
  inputs,
  config,
  pkgs,
  lib,
  ...
}:
{
  # Set the host platform for Darwin
  nixpkgs.hostPlatform = lib.mkDefault "aarch64-darwin";
  # Darwin-specific system settings
  system.configurationRevision = null;
  # Set primary user for user-level launchd agents
  system.primaryUser = config.hostSpec.username;
  # Enable sudo authentication via Yubikey/Touch ID
  #security.pam.services.sudo_local.touchIdAuth = true;
  environment.etc."pam.d/sudo_local".text = ''
    # YubiKey auth
    auth       sufficient     ${pkgs.pam_u2f}/lib/security/pam_u2f.so cue [cue_prompt=Touch YubiKey for sudo]
    # Fallback to Touch ID
    auth       sufficient     pam_tid.so
  '';

  #
  # ========== Nix Helper ==========
  #
  # NOTE: Darwin doesn't have programs.nh module, so we set the environment variable directly
  # environment.variables = {
  #   NH_FLAKE = "${config.hostSpec.home}/nix-src/nix-config";
  # };

  #
  # ========== Darwin settings ==========
  #
  # Reference: https://nix-darwin.github.io/nix-darwin/manual/index.html
  system.defaults = {
    # false means “One at a time” true means “All at once”
    WindowManager.AppWindowGroupingBehavior = false;

    NSGlobalDomain = {
      #Sets the speed of window resizing
      NSWindowResizeTime = 0.5;
    };
    finder = {
      AppleShowAllExtensions = true;
      AppleShowAllFiles = true;
      CreateDesktop = true;
      FXEnableExtensionChangeWarning = false;
      ShowPathbar = true;
      ShowStatusBar = true;
      _FXShowPosixPathInTitle = true;
    };
    dock = {
      autohide = false;
      show-recents = false;
      expose-animation-duration = 0.2;
      autohide-time-modifier = 0.2;
      tilesize = 50;
      magnification = false;
      largesize = 64;
      orientation = "bottom";
      mineffect = "scale";
      launchanim = false;
    };
    ".GlobalPreferences"."com.apple.mouse.scaling" = -1.0;
  };

  # ========== Nix Registry & NixPath ==========
  #
  # NOTE: On Darwin, we need to use mkForce to override nix-darwin's defaults
  nix = {
    # This will add each flake input as a registry
    # To make nix3 commands consistent with your flake
    registry = lib.mkForce (lib.mapAttrs (_: value: { flake = value; }) inputs);

    # This will add your inputs to the system's legacy channels
    # Making legacy nix commands consistent as well, awesome!
    nixPath = lib.mkForce (
      lib.mapAttrsToList (key: value: "${key}=${value.to.path}") config.nix.registry
    );
    # Enable linux-builder for Darwin
    #settings.linux-builder.enable = true;
    # disable case-sensitive path hack
    use-case-hack = false;
  };
}
