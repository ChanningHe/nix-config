# darwin-nix Dock Killer
#
# Automatically restarts Dock when display configuration changes.
# Solves the common macOS bug where Dock freezes and wallpaper goes black
# after plugging/unplugging external displays.
#
# Architecture:
#   ~/.config/darwin-nix/dock-killer/
#     ├── monitor.sh            (display event monitor daemon)
#     ├── killer.log            (unified log file)
#     ├── stdout.log            (LaunchAgent stdout)
#     └── stderr.log            (LaunchAgent stderr)
#
#   ~/Library/LaunchAgents/com.darwin-nix.dock-killer.plist
#     └── Keeps monitor.sh running continuously (KeepAlive)
#
# Features:
# - Real-time display event monitoring via log stream
# - Debounce logic to avoid repeated restarts during rapid plug/unplug
# - INFO/DEBUG log levels to control verbosity
# - Zero-impact solution: killall Dock is safe and triggers automatic restart

{
  config,
  lib,
  ...
}:
let
  cfg = config.dockAutoKiller;

  # Monitor script that watches display events and kills Dock
  monitorScript = ''
    #!/usr/bin/env bash
    # Dock Killer - Monitor display changes and restart Dock

    set -euo pipefail

    SCRIPT_DIR="$HOME/.config/darwin-nix/dock-killer"
    LOG_FILE="$SCRIPT_DIR/killer.log"
    DELAY=${toString cfg.debounceDelay}
    LOG_LEVEL="${cfg.logLevel}"
    LAST_EVENT_FILE="/tmp/dock-killer-last-event-$$"

    # Cleanup on exit
    trap 'rm -f "$LAST_EVENT_FILE"' EXIT

    # Log functions
    log_info() {
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
      logger -t dock-killer "$*"
    }

    log_debug() {
      if [ "$LOG_LEVEL" = "DEBUG" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $*" | tee -a "$LOG_FILE"
        logger -t dock-killer "[DEBUG] $*"
      fi
    }

    log_info "Dock Killer started (log level: $LOG_LEVEL, debounce: ''${DELAY}s)"

    # Listen to display-related system logs
    # CoreDisplay subsystem captures all display configuration changes
    log stream --predicate 'subsystem == "com.apple.CoreDisplay"' 2>/dev/null | \
    while IFS= read -r line; do
      log_debug "Display event: $line"

      # Update last event timestamp
      echo "$(date +%s)" > "$LAST_EVENT_FILE"
      log_debug "Event timestamp updated, debounce timer started"

      # Background debounce process
      (
        sleep "$DELAY"

        # Check if this is still the last event
        if [ -f "$LAST_EVENT_FILE" ]; then
          last=$(cat "$LAST_EVENT_FILE" 2>/dev/null || echo 0)
          now=$(date +%s)
          elapsed=$((now - last))

          if [ "$elapsed" -ge "$DELAY" ]; then
            log_info "Display change detected, killing Dock..."

            if killall Dock 2>/dev/null; then
              log_info "Dock killed successfully"
            else
              log_info "Dock kill command executed (Dock may already be restarting)"
            fi

            # Clean up timestamp file
            rm -f "$LAST_EVENT_FILE"
          else
            log_debug "New event arrived during debounce, skip action (elapsed: ''${elapsed}s)"
          fi
        else
          log_debug "Event file removed, skip action"
        fi
      ) &
    done

    log_info "Dock Killer stopped"
  '';

in
{
  options.dockAutoKiller = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable automatic Dock restart on display configuration changes";
    };

    debounceDelay = lib.mkOption {
      type = lib.types.int;
      default = 3;
      description = "Delay in seconds before executing Dock kill (debounce window)";
    };

    logLevel = lib.mkOption {
      type = lib.types.enum [
        "INFO"
        "DEBUG"
      ];
      default = "INFO";
      description = ''
        Log level control:
        - INFO: Only log Dock kill actions
        - DEBUG: Log all display events and debounce process
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Install monitor script
    system.activationScripts.postActivation.text = ''
      echo "Installing darwin-nix Dock Killer..."

      KILLER_DIR="/Users/${config.hostSpec.username}/.config/darwin-nix/dock-killer"
      mkdir -p "$KILLER_DIR"
      chown "${config.hostSpec.username}" "$KILLER_DIR"

      # Monitor script
      cat > "$KILLER_DIR/monitor.sh" <<'MONITOR_SCRIPT_EOF'
      ${monitorScript}
      MONITOR_SCRIPT_EOF
      chmod +x "$KILLER_DIR/monitor.sh"
      chown "${config.hostSpec.username}" "$KILLER_DIR/monitor.sh"

      # Initialize log file
      touch "$KILLER_DIR/killer.log"
      chown "${config.hostSpec.username}" "$KILLER_DIR/killer.log"

      echo "✓ Installed Dock Killer in $KILLER_DIR"
      echo "  - monitor.sh: Display event monitor daemon"
      echo "  - killer.log: Unified log file"
      echo "  - Log level: ${cfg.logLevel}"
      echo "  - Debounce delay: ${toString cfg.debounceDelay}s"

      # Reload LaunchAgent if already loaded
      AGENT_LABEL="com.darwin-nix.dock-killer"
      PLIST_PATH="/Users/${config.hostSpec.username}/Library/LaunchAgents/$AGENT_LABEL.plist"

      if sudo -u "${config.hostSpec.username}" launchctl list | grep -q "$AGENT_LABEL"; then
        echo "Reloading LaunchAgent..."
        sudo -u "${config.hostSpec.username}" launchctl bootout gui/"$(id -u ${config.hostSpec.username})" "$PLIST_PATH" 2>/dev/null || true
        sudo -u "${config.hostSpec.username}" launchctl bootstrap gui/"$(id -u ${config.hostSpec.username})" "$PLIST_PATH" 2>/dev/null || true
        echo "✓ LaunchAgent reloaded"
      fi
    '';

    # LaunchAgent for continuous monitoring
    launchd.user.agents.darwin-nix-dock-killer = {
      serviceConfig = {
        ProgramArguments = [
          "/Users/${config.hostSpec.username}/.config/darwin-nix/dock-killer/monitor.sh"
        ];

        # Keep the monitor running at all times
        KeepAlive = true;

        # Start on login
        RunAtLoad = true;

        # Log output
        StandardOutPath = "/Users/${config.hostSpec.username}/.config/darwin-nix/dock-killer/stdout.log";
        StandardErrorPath = "/Users/${config.hostSpec.username}/.config/darwin-nix/dock-killer/stderr.log";
      };
    };
  };
}
