# Dock Killer Configuration
#
# Automatically restarts Dock when display configuration changes.
# Solves the common macOS bug where Dock freezes and wallpaper goes black
# after plugging/unplugging external displays.
#
# Usage:
#   imports = [ "hosts/common/optional/darwin/dock-killer.nix" ];
#
# Configuration Options:
#   dockAutoKiller.enable = true;           # Enable the killer (default: false)
#   dockAutoKiller.debounceDelay = 3;       # Delay in seconds (default: 3)
#   dockAutoKiller.logLevel = "INFO";       # "INFO" or "DEBUG" (default: "INFO")
#   dockAutoKiller.forceKill = false;       # Use SIGKILL (-9) instead of SIGTERM (default: false)
#
# Features:
# - Real-time display event monitoring
# - Debounce logic to avoid repeated restarts
# - INFO/DEBUG log levels
# - Zero-impact solution: killall Dock is safe

{ ... }:
{
  dockAutoKiller = {
    enable = true;
    debounceDelay = 5; # Change this value to adjust delay (in seconds)
    logLevel = "INFO"; # Change to "DEBUG" for verbose logging
    forceKill = true; # Uncomment if normal killall doesn't work (uses SIGKILL -9)
  };
}
