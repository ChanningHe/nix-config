# darwin-nix SMB Auto-Mounter
#
# Elegant SMB mounting for macOS using native osascript.
# Periodic health checks ensure mounts stay alive.
#
# Architecture:
#   ~/.config/darwin-nix/smb-mounter/
#     ├── mount.sh              (mount script)
#     ├── check.sh              (health check script, called by LaunchAgent)
#     └── mounts.log            (unified log)
#
#   ~/Library/LaunchAgents/com.darwin-nix.smb-mounter.plist
#     └── Runs check.sh every 5 minutes
#
# Features:
# - Uses macOS Keychain for password storage (after first mount)
# - Mounts appear in Finder sidebar automatically
# - Health checks prevent redundant mount attempts
# - Centralized logging

{
  config,
  lib,
  inputs,
  ...
}:
let
  cfg = config.networkStorage;

  # Read network storage info from nix-secrets
  networkStorageInfo = inputs.nix-secrets.networkStorageInfo or { };
  hostConfig = networkStorageInfo.${cfg.hostname} or { };
  clientConfig = hostConfig.client or { };
  sambaClientConfig = clientConfig.samba or null;

  sambaClientEnabled = cfg.client.samba.enable && sambaClientConfig != null;

  # Flatten all mounts from all servers
  allMounts =
    if sambaClientEnabled then
      lib.flatten (
        lib.mapAttrsToList (
          serverName: serverConfig:
          map (
            mount:
            mount
            // {
              serverName = serverName;
              # Password is optional - macOS Keychain handles it after first mount
              credentials =
                if (config.sops.secrets ? "samba-${serverName}") then
                  config.sops.secrets."samba-${serverName}".path
                else
                  null;
            }
          ) (serverConfig.mounts or [ ])
        ) (sambaClientConfig.servers or { })
      )
    else
      [ ];

  # Generate mount function for a single share
  mkMountFunction =
    mount:
    let
      serverPath = lib.removePrefix "//" mount.share;
      mountName = builtins.baseNameOf mount.mountPoint;
      credFile = if mount.credentials != null then mount.credentials else "";
    in
    ''
       mount_${lib.replaceStrings [ "-" "/" "." ] [ "_" "_" "_" ] mountName}() {
        local server_path="${serverPath}"
        local mount_name="${mountName}"
        local credentials_file="${credFile}"

        # Check if already mounted by looking for the exact share URL
        # Use " on " as delimiter to ensure exact match (avoid substring issues like Media vs MediaCentre)
        if ! mount | grep -qF "//$USERNAME@$server_path on "; then
          # Not mounted at all
          log "→ $mount_name: not mounted, mounting..."
        else
          # Already mounted, get the actual mount point
          local mount_dir
          mount_dir=$(mount | grep -F "//$USERNAME@$server_path on " | head -1 | awk '{print $3}')

          # Lightweight health check: just stat the mount point itself
          # Don't use 'ls' as it triggers directory listing which can be slow on SMB
          if timeout 3 stat "$mount_dir" >/dev/null 2>&1; then
            # Mount is healthy, no action needed
            return 0
          else
            # stat failed - mount point is truly unresponsive
            log "⚠ $mount_name: mount point unresponsive at $mount_dir, remounting..."
            diskutil unmount force "$mount_dir" 2>/dev/null || true
            sleep 2
          fi
        fi

        # Extract server IP/hostname from server_path (format: "server/share")
        local server_host
        server_host=$(echo "$server_path" | cut -d'/' -f1)

        # Check if SMB port (445) is reachable before attempting mount
        # Use nc (netcat) with 2-second timeout - more reliable than ping
        if ! nc -z -w 2 "$server_host" 445 >/dev/null 2>&1; then
          log "✗ $mount_name: server $server_host unreachable (port 445), skipping mount"
          return 1
        fi

        # Build SMB URL
        local smb_url
        if [ -n "$credentials_file" ] && [ -f "$credentials_file" ]; then
          local password
          password=$(tr -d '\n' < "$credentials_file")

          if command -v ruby >/dev/null 2>&1; then
            local pass_enc
            pass_enc=$(ruby -r cgi -e "print CGI.escape('$password')")
            smb_url="smb://$USERNAME:$pass_enc@$server_path"
          else
            smb_url="smb://$USERNAME:$password@$server_path"
          fi
        else
          smb_url="smb://$USERNAME@$server_path"
        fi

        # Attempt mount
        log "→ $mount_name: mounting..."
        if osascript -e "mount volume \"$smb_url\"" 2>/dev/null; then
          log "✓ $mount_name: mounted successfully"
          return 0
        else
          log "✗ $mount_name: mount failed"
          return 1
        fi
      }
    '';

  # Mount script (called manually or on first run)
  mountScript = ''
    #!/usr/bin/env bash
    # darwin-nix SMB Mounter - Mount Script
    # Mounts all configured SMB shares

    set -euo pipefail

    # Ensure full PATH for all commands
    export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.nix-profile/bin:/run/current-system/sw/bin"

    SCRIPT_DIR="$HOME/.config/darwin-nix/smb-mounter"
    LOG_FILE="$SCRIPT_DIR/mounts.log"
    USERNAME="${config.hostSpec.username}"

    log() {
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
    }

    ${lib.concatMapStrings mkMountFunction allMounts}

    log "========== Mounting all shares =========="
    ${lib.concatMapStrings (
      mount:
      let
        mountName = builtins.baseNameOf mount.mountPoint;
      in
      "mount_${lib.replaceStrings [ "-" "/" "." ] [ "_" "_" "_" ] mountName} || true\n"
    ) allMounts}
    log "========== Mount cycle complete =========="
  '';

  # Health check script (called by LaunchAgent every N minutes)
  checkScript = ''
    #!/usr/bin/env bash
    # darwin-nix SMB Mounter - Health Check Script
    # Periodically checks mount health and remounts if needed

    set -euo pipefail

    # LaunchAgent runs with minimal PATH, set it explicitly
    export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.nix-profile/bin:/run/current-system/sw/bin"

    SCRIPT_DIR="$HOME/.config/darwin-nix/smb-mounter"
    LOG_FILE="$SCRIPT_DIR/mounts.log"
    USERNAME="${config.hostSpec.username}"

    log() {
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
    }

    ${lib.concatMapStrings mkMountFunction allMounts}

    # Check all mounts
    ${lib.concatMapStrings (
      mount:
      let
        mountName = builtins.baseNameOf mount.mountPoint;
      in
      "mount_${lib.replaceStrings [ "-" "/" "." ] [ "_" "_" "_" ] mountName} || true\n"
    ) allMounts}
  '';

in
{
  options.networkStorage = {
    hostname = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      description = "Hostname to lookup in networkStorageInfo";
    };

    client.samba = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable darwin-nix SMB auto-mounter";
      };

      checkInterval = lib.mkOption {
        type = lib.types.int;
        default = 300;
        description = "Mount health check interval in seconds (default: 5 minutes)";
      };
    };
  };

  config = lib.mkIf sambaClientEnabled {
    # Install scripts
    system.activationScripts.postActivation.text = ''
      echo "Installing darwin-nix SMB auto-mounter..."

      MOUNTER_DIR="/Users/${config.hostSpec.username}/.config/darwin-nix/smb-mounter"
      mkdir -p "$MOUNTER_DIR"
      chown "${config.hostSpec.username}" "$MOUNTER_DIR"

      # Mount script
      cat > "$MOUNTER_DIR/mount.sh" <<'MOUNT_SCRIPT_EOF'
      ${mountScript}
      MOUNT_SCRIPT_EOF
      chmod +x "$MOUNTER_DIR/mount.sh"
      chown "${config.hostSpec.username}" "$MOUNTER_DIR/mount.sh"

      # Health check script
      cat > "$MOUNTER_DIR/check.sh" <<'CHECK_SCRIPT_EOF'
      ${checkScript}
      CHECK_SCRIPT_EOF
      chmod +x "$MOUNTER_DIR/check.sh"
      chown "${config.hostSpec.username}" "$MOUNTER_DIR/check.sh"

      # Initialize log file
      touch "$MOUNTER_DIR/mounts.log"
      chown "${config.hostSpec.username}" "$MOUNTER_DIR/mounts.log"

      echo "✓ Installed scripts in $MOUNTER_DIR"
      echo "  - mount.sh: Manual mount all shares"
      echo "  - check.sh: Periodic health check (called by LaunchAgent)"
      echo "  - mounts.log: Unified log file"
    '';

    # LaunchAgent for periodic health checks
    launchd.user.agents.darwin-nix-smb-mounter = {
      serviceConfig = {
        ProgramArguments = [
          "/Users/${config.hostSpec.username}/.config/darwin-nix/smb-mounter/check.sh"
        ];
        RunAtLoad = true; # Run on login (initial mount)
        StartInterval = cfg.client.samba.checkInterval; # Periodic check
        StandardOutPath = "/Users/${config.hostSpec.username}/.config/darwin-nix/smb-mounter/stdout.log";
        StandardErrorPath = "/Users/${config.hostSpec.username}/.config/darwin-nix/smb-mounter/stderr.log";
      };
    };
  };
}
