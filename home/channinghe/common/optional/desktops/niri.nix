# User-level niri compositor settings: keybinds, layout, window rules, startup programs.
# NOTE: programs.niri.settings is available here because nixosModules.niri
# auto-imports homeModules.config for all home-manager users.
{
  pkgs,
  lib,
  ...
}:
let
  noctalia =
    cmd:
    [
      "noctalia-shell"
      "ipc"
      "call"
    ]
    ++ (lib.splitString " " cmd);
in
{
  programs.alacritty.enable = true;

  programs.niri.settings = {
    # ── Input ──────────────────────────────────────────────
    input = {
      keyboard.repeat-delay = 300;
      keyboard.repeat-rate = 40;
      mouse.accel-profile = "flat";
      focus-follows-mouse.enable = true;
    };

    # ── Hotkey Overlay ─────────────────────────────────────
    # Show available keybinds on first launch (dismiss with Escape)
    hotkey-overlay.skip-at-startup = false;

    # ── Layout ─────────────────────────────────────────────
    layout = {
      gaps = 8;
      center-focused-column = "on-overflow";

      preset-column-widths = [
        { proportion = 1.0 / 3.0; }
        { proportion = 1.0 / 2.0; }
        { proportion = 2.0 / 3.0; }
      ];
      default-column-width = {
        proportion = 1.0 / 2.0;
      };

      focus-ring = {
        enable = true;
        width = 2;
        active.color = "#7aa2f7";
        inactive.color = "#414868";
      };
      border.enable = false;
      shadow.enable = true;
    };

    # ── Spawn at Startup ──────────────────────────────────
    # Noctalia Shell is started via its own systemd service (noctalia.nix),
    # so we only need non-shell startup items here.
    spawn-at-startup = [
      { command = [ "${pkgs.xwayland-satellite}/bin/xwayland-satellite" ]; }
    ];

    # ── Window Rules ──────────────────────────────────────
    window-rules = [
      # Rounded corners for all windows (matches Noctalia's aesthetic)
      {
        geometry-corner-radius =
          let
            r = 10.0;
          in
          {
            top-left = r;
            top-right = r;
            bottom-left = r;
            bottom-right = r;
          };
        clip-to-geometry = true;
      }
    ];

    # ── Debug ─────────────────────────────────────────────
    # Required for Noctalia notification actions and window activation
    debug.honor-xdg-activation-with-invalid-serial = true;

    # ── Layer Rules ───────────────────────────────────────
    # Noctalia overview wallpaper on the backdrop layer
    layer-rules = [
      {
        matches = [
          { namespace = "^noctalia-overview.*"; }
        ];
        place-within-backdrop = true;
      }
    ];

    # ── Keybinds ──────────────────────────────────────────
    # All actions use explicit `.action.name = args;` attribute syntax.
    # No-arg actions pass `[]`, parameterized actions pass their value.
    binds = {
      # -- Window Management --
      "Mod+Q".action.close-window = [ ];
      "Mod+F".action.maximize-column = [ ];
      "Mod+Shift+F".action.fullscreen-window = [ ];
      "Mod+C".action.center-column = [ ];

      # Focus navigation (arrow keys)
      "Mod+Left".action.focus-column-left = [ ];
      "Mod+Right".action.focus-column-right = [ ];
      "Mod+Up".action.focus-window-or-workspace-up = [ ];
      "Mod+Down".action.focus-window-or-workspace-down = [ ];

      # Focus navigation (vim keys)
      "Mod+H".action.focus-column-left = [ ];
      "Mod+L".action.focus-column-right = [ ];
      "Mod+K".action.focus-window-or-workspace-up = [ ];
      "Mod+J".action.focus-window-or-workspace-down = [ ];

      # Move windows (arrow keys)
      "Mod+Shift+Left".action.move-column-left = [ ];
      "Mod+Shift+Right".action.move-column-right = [ ];
      "Mod+Shift+Up".action.move-window-up-or-to-workspace-up = [ ];
      "Mod+Shift+Down".action.move-window-down-or-to-workspace-down = [ ];

      # Move windows (vim keys)
      "Mod+Shift+H".action.move-column-left = [ ];
      "Mod+Shift+L".action.move-column-right = [ ];
      "Mod+Shift+K".action.move-window-up-or-to-workspace-up = [ ];
      "Mod+Shift+J".action.move-window-down-or-to-workspace-down = [ ];

      # Column width presets (1/3, 1/2, 2/3)
      "Mod+R".action.switch-preset-column-width = [ ];
      "Mod+Minus".action.set-column-width = "-10%";
      "Mod+Equal".action.set-column-width = "+10%";

      # Workspaces (by index)
      "Mod+1".action.focus-workspace = 1;
      "Mod+2".action.focus-workspace = 2;
      "Mod+3".action.focus-workspace = 3;
      "Mod+4".action.focus-workspace = 4;
      "Mod+5".action.focus-workspace = 5;
      "Mod+Shift+1".action.move-column-to-workspace = 1;
      "Mod+Shift+2".action.move-column-to-workspace = 2;
      "Mod+Shift+3".action.move-column-to-workspace = 3;
      "Mod+Shift+4".action.move-column-to-workspace = 4;
      "Mod+Shift+5".action.move-column-to-workspace = 5;

      # Consume / expel windows within columns
      "Mod+Comma".action.consume-window-into-column = [ ];
      "Mod+Period".action.expel-window-from-column = [ ];

      # Tabbed columns
      "Mod+W".action.toggle-column-tabbed-display = [ ];

      # -- Screenshots --
      "Print".action.screenshot = [ ];
      "Mod+Print".action.screenshot-screen = { };
      "Mod+Shift+Print".action.screenshot-window = { };

      # -- Overview (like macOS Mission Control) --
      "Mod+Tab".action.toggle-overview = [ ];

      # -- Applications --
      "Mod+T".action.spawn = [ "alacritty" ];
      "Mod+Return".action.spawn = [ "alacritty" ];

      # -- Noctalia Shell Integration --
      "Mod+Space".action.spawn = noctalia "launcher toggle";
      "Mod+Escape".action.spawn = noctalia "sessionMenu toggle";

      # -- Media / Hardware Keys --
      "XF86AudioRaiseVolume".action.spawn = noctalia "volume increase";
      "XF86AudioLowerVolume".action.spawn = noctalia "volume decrease";
      "XF86AudioMute".action.spawn = noctalia "volume muteOutput";

      # -- Session --
      "Mod+Shift+E".action.quit = [ ];
    };
  };
}
