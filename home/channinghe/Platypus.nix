#NOTE(starter): Unlike the host-level host files that are structured as `nix-config/hosts/[platform]/[hostname]/default.nix`
# the corresponding home-level files are housed in each user's home-level config directory. This allows you to customize
# user-specific, home-manager configurations on a per user basis. The `home/common/optional/foo` configs, along with
# `home/common/core` allow you to import the specific home-manager configs you want for each host
{ ... }:
{
  imports = [
    #
    # ========== Required Configs ==========
    #
    common/core

    #
    # ========== Host-specific Optional Configs ==========
    #
    common/optional/browsers
    common/optional/desktops
    # common/optional/comms
    common/optional/media
    # uncommit to auto add ssh-private-key && age user key
    # common/optional/sops.nix
  ];

  # ── Platypus Display Output ──────────────────────────
  # Run `niri msg outputs` to find exact connector name and refresh rate.
  # Replace "DP-1" with actual output (e.g. HDMI-A-1, DP-2, etc).
  programs.niri.settings.outputs."HDMI-A-3" = {
    mode = {
      width = 3840;
      height = 2160;
      refresh = 144.0;
    };
    scale = 1.5;
    variable-refresh-rate = "on-demand";
  };

  sshClients.enableAll = true;
}
