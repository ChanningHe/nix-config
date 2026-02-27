# Noctalia Shell: desktop shell providing bar, launcher, notifications, lock screen, wallpaper.
# Uses Noctalia's home-manager module for declarative configuration and systemd auto-start.
{ inputs, ... }:
{
  imports = [
    inputs.noctalia.homeModules.default
  ];

  programs.noctalia-shell = {
    enable = true;
    systemd.enable = true;

    settings = {
      bar = {
        position = "top";
        density = "default";
        backgroundOpacity = 0.9;
        floating = false;
        widgets = {
          left = [
            { id = "Launcher"; }
            { id = "Clock"; }
            { id = "ActiveWindow"; }
            { id = "MediaMini"; }
          ];
          center = [
            {
              id = "Workspace";
              hideUnoccupied = false;
              labelMode = "none";
            }
          ];
          right = [
            { id = "Tray"; }
            { id = "NotificationHistory"; }
            { id = "Volume"; }
            { id = "Brightness"; }
            { id = "ControlCenter"; }
          ];
        };
      };

      general = {
        radiusRatio = 0.8;
        animationSpeed = 1;
        lockOnSuspend = true;
        showChangelogOnStartup = false;
        telemetryEnabled = false;
      };

      wallpaper = {
        enabled = true;
        overviewEnabled = true;
        fillMode = "crop";
        overviewBlur = 0.4;
        overviewTint = 0.6;
      };

      colorSchemes = {
        predefinedScheme = "Noctalia (default)";
        darkMode = true;
      };

      notifications = {
        enabled = true;
        location = "top_right";
        normalUrgencyDuration = 8;
        criticalUrgencyDuration = 15;
      };

      appLauncher = {
        position = "center";
        sortByMostUsed = true;
        terminalCommand = "alacritty -e";
      };
    };
  };
}
