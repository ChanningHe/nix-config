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
    debounceDelay = 3; # Change this value to adjust delay (in seconds)
    logLevel = "INFO"; # Change to "DEBUG" for verbose logging
  };
}
