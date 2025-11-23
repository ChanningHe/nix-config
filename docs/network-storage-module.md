# Network Storage Module Documentation

This module provides centralized NFS and Samba server/client configuration management. Sensitive configurations (paths, shares, permissions, mount points) are stored in the private `nix-secrets` repository, while host configurations are automatically enabled based on the secrets.

## Architecture

```
nix-secrets/nix/network-storage.nix       →  Configuration Data + Enable Flags (private)
                                             ↓
nix-config/modules/hosts/common/          →  Module Logic (public)
network-storage.nix                          ↓
                                             ↓
hosts/common/optional/network-storage.nix →  Auto-enable based on secrets
                                             ↓
hosts/nixos/${hostname}/default.nix       →  Just import optional file!
```

**Key Feature**: Services are automatically enabled based on configurations in nix-secrets.
No need to manually set `enable = true` in each host!

## Important: New Samba Client Structure (v2)

**Breaking Change**: The Samba client configuration structure has been updated to support multiple servers and automatic SOPS credential management.

### What Changed

**Old Structure (Deprecated)**:
```nix
samba = {
  enable = true;
  mounts = [
    {
      share = "//nas.local/media";
      mountPoint = "/mnt/nas-media";
      credentials = config.sops.secrets."samba-creds".path;  # Manual
    }
  ];
};
```

**New Structure (Current)**:
```nix
samba = {
  enable = true;
  servers = {
    nas-main = {  # Server name = SOPS key name
      mounts = [
        {
          share = "//nas.local/media";
          mountPoint = "/mnt/nas-media";
          # credentials auto-injected as config.sops.secrets."samba-nas-main".path
        }
      ];
    };
  };
};
```

### Benefits of New Structure

1. ✅ **Multi-server support**: Organize mounts by server with clear naming
2. ✅ **Automatic SOPS management**: No need to manually configure `sops.secrets`
3. ✅ **Reduced repetition**: Credentials path auto-injected per server
4. ✅ **Type-safe**: Server names directly map to SOPS keys
5. ✅ **Consistent across platforms**: Same structure for NixOS and Darwin

### SOPS Configuration

For the new structure, organize your SOPS secrets by server:

```yaml
# secrets/${hostname}.yaml
samba:
    nas-main: |
        username=myuser
        password=mypassword
    backup-server: |
        username=backup_user
        password=backup_pass
```

The module automatically creates:
- `sops.secrets."samba-nas-main"` with key `"samba/nas-main"`
- `sops.secrets."samba-backup-server"` with key `"samba/backup-server"`

## Configuration Structure

### In nix-secrets (Private)

File: `nix-secrets/nix/network-storage.nix`

```nix
{
  networkStorageInfo = {
    ${hostname} = {
      # Server Configuration (optional)
      server = {
        # NFS Server
        nfs = {
          enable = true;  # Enable flag
          exports = ''
            /export/data 192.168.1.0/24(rw,sync,no_subtree_check)
            /export/media 192.168.1.0/24(ro,sync,no_subtree_check)
          '';
        };

        # Samba Server (follows services.samba.settings structure)
        samba = {
          enable = true;  # Enable flag
          global = {
            workgroup = "WORKGROUP";
            "server string" = "Samba Server";
            security = "user";
          };

          # Share configurations (each share is a top-level key)
          data = {
            path = "/srv/samba/data";
            "read only" = "no";
            browseable = "yes";
            "guest ok" = "no";
            "valid users" = "username";
          };
        };
      };

      # Client Configuration (optional)
      client = {
        # NFS Client
        nfs = {
          enable = true;  # Enable flag
          mounts = [
            {
              server = "nas.local";
              remotePath = "/export/data";
              mountPoint = "/mnt/nas-data";
              options = [ "vers=4" "soft" ];
            }
          ];
        };

        # Samba Client (New Structure)
        samba = {
          enable = true;  # Enable flag
          # Organize mounts by server (supports multiple SMB servers)
          servers = {
            # Server name (corresponds to sops key "samba/{servername}")
            nas-main = {
              mounts = [
                {
                  share = "//nas.local/media";
                  mountPoint = "/mnt/nas-media";
                  # credentials auto-injected from config.sops.secrets."samba-nas-main".path
                  options = [ "ro" "uid=1000" ];
                }
              ];
            };
            # Additional servers can be added here
            backup-server = {
              mounts = [
                {
                  share = "//backup.local/data";
                  mountPoint = "/mnt/backup-data";
                  options = [ "rw" "uid=1000" ];
                }
              ];
            };
          };
        };
      };
    };
  };
}
```

### In nix-config (Public)

File: `hosts/nixos/${hostname}/default.nix`

## Usage Examples

### Example 1: Auto-Enable Everything (Recommended)

```nix
# hosts/nixos/Poecilia/default.nix
{
  imports = [
    # ... other imports
    (lib.custom.relativeToRoot "hosts/common/optional/network-storage.nix")
  ];

  # That's it! Services are auto-enabled based on nix-secrets
}
```

**Result**: If `networkStorageInfo.Poecilia.server.nfs.enable = true` in nix-secrets,
NFS server will be automatically enabled. Same for Samba, and clients.

### Example 2: Add Common Non-Sensitive Settings

```nix
# hosts/common/optional/network-storage.nix
{
  networkStorage = {
    # Services auto-enabled from secrets

    # Optional: Add common settings for all hosts
    server.nfs.extraConfig = ''
      # Public read-only export (non-sensitive)
      /export/public *(ro,sync,no_subtree_check)
    '';

    server.samba.extraGlobalConfig = {
      # Force SMB2+ for security
      "server min protocol" = "SMB2";
      "client max protocol" = "SMB3";
    };

    # Add common mount options for clients
    client.nfs.extraOptions = [ "soft" "timeo=30" ];
    client.samba.extraOptions = [ "vers=3.0" ];
  };
}
```

### Example 3: Manual Override (If Needed)

If you don't want auto-enable, you can manually control:

```nix
# hosts/nixos/CustomHost/default.nix
{
  # Don't import optional/network-storage.nix

  networkStorage = {
    server.nfs.enable = lib.mkForce true;   # Force enable
    server.samba.enable = lib.mkForce false; # Force disable
  };
}
```

### Example 4: Custom Hostname Lookup

If the host's system hostname differs from the key in `networkStorageInfo`:

```nix
{
  networkStorage = {
    hostname = "CustomHostName";  # Override lookup key
  };
}
```

## Features

### Automatic Configuration
- **Firewall Rules**: Automatically opens required ports for enabled services
  - NFS: TCP/UDP 111, 2049, 20048
  - Samba: TCP 139, 445; UDP 137, 138

### Validation
- Warns if service is enabled but no configuration exists in `nix-secrets`
- Prevents silent misconfigurations

### Separation of Concerns
- **Sensitive data** (paths, user lists, network ranges) → `nix-secrets` (private)
- **Service enablement** (booleans, global policies) → `nix-config` (public)

## NFS Configuration Format

Follows standard `/etc/exports` format (see `exports(5)` man page):

```
<export_path> <client_spec>(options)
```

**Example:**
```nix
exports = ''
  /export/data 192.168.1.0/24(rw,sync,no_subtree_check,fsid=0)
  /export/media 10.1.10.0/24(ro,all_squash,anonuid=65534,anongid=65534)
  /export/home *(rw,sync,no_root_squash)
'';
```

## Samba Configuration Format

Follows `services.samba.settings` structure, which maps to `smb.conf` INI format (see `smb.conf(5)` man page):

### Structure in nix-secrets
```nix
server.samba = {
  enable = true;
  # Global section (required)
  global = {
    workgroup = "WORKGROUP";
    "server string" = "My Samba Server";
    security = "user";
    "map to guest" = "Bad User";
    "log level" = "1";
  };

  # Share sections (share name = attrset of options)
  sharename = {
    path = "/path/to/share";
    "read only" = "yes";  # Use quoted keys for spaces
    browseable = "yes";
    "guest ok" = "no";
    "valid users" = "user1 user2";
    "create mask" = "0644";
    "directory mask" = "0755";
  };

  anothershare = {
    path = "/another/path";
    writable = "yes";
  };
};
```

**Important Notes:**
- Each share is a **top-level key** under `sambaServer`, not nested under `shares`
- The `global` section is also a top-level key
- Option names with spaces must be quoted (e.g., `"read only"`)
- This structure directly maps to `services.samba.settings`

## Security Best Practices

1. **Always store sensitive data in nix-secrets**:
   - Actual file paths
   - User/group names
   - Network ranges
   - Share configurations

2. **Only use extraConfig for generic policies**:
   - Protocol versions
   - Logging levels
   - Timeout settings

3. **Review firewall rules**:
   - Default allows all networks on opened ports
   - Add host-specific restrictions if needed

4. **Regular audits**:
   - Review NFS exports for overly permissive settings
   - Check Samba shares for guest access
   - Verify user access lists

## Troubleshooting

### Service Enabled but Not Working

Check for warnings in build output:
```bash
nixos-rebuild build --flake .#hostname
```

Look for:
```
warning: networkStorage.server.nfs.enable is true but no NFS configuration found for host 'hostname'.
Expected configuration at: networkStorageInfo.hostname.server.nfs in nix-secrets.
```

**Solution**: Add configuration to `nix-secrets/nix/network-storage.nix`

### Port Already in Use

If NFS/Samba ports conflict with existing services:
1. Check `systemctl status rpcbind nfs-server smbd`
2. Review `networking.firewall` settings
3. Disable conflicting services

### Permission Denied

**NFS**: Check directory permissions and export options (`no_root_squash` vs `all_squash`)

**Samba**:
1. Verify user exists: `id username`
2. Set Samba password: `smbpasswd -a username`
3. Check `valid users` in share configuration

## Darwin (macOS) Support

This module supports automatic SMB client mounting on Darwin (macOS) systems using a different implementation approach than NixOS.

### Platform Differences

| Feature | NixOS | Darwin |
|---------|-------|--------|
| **Mount Mechanism** | `fileSystems` (systemd) | `launchd.agents` |
| **Mount Command** | `mount.cifs` | `mount_smbfs` |
| **Credentials** | `credentials=` option | URL format `//user:pass@server` |
| **Network Awareness** | systemd network targets | launchd `WatchPaths` |
| **Health Checks** | systemd unit monitoring | Custom health check agents |

### Darwin Architecture

The Darwin implementation uses a **dual-agent architecture**:

#### Agent 1: Mount Agent (Network-Reactive)
- Responds to network configuration changes
- Runs at system startup (`RunAtLoad = true`)
- Monitors network files via `WatchPaths`:
  - `/Library/Preferences/SystemConfiguration/com.apple.airport.preferences.plist`
  - `/etc/resolv.conf`
- 30-second throttle to prevent rapid re-triggering

#### Agent 2: Health Check Agent (Periodic)
- Runs every 5 minutes by default (configurable)
- Checks if mount points are accessible
- Automatically triggers remount on failure
- Can be disabled by setting `healthCheckInterval = 0`

### Darwin Configuration

#### Step 1: Enable in Host Config

```nix
# hosts/darwin/YourMacBook/default.nix
{
  imports = [
    (lib.custom.relativeToRoot "hosts/common/optional/network-storage-darwin.nix")
  ];
}
```

#### Step 2: Configure in nix-secrets

```nix
# nix-secrets/nix/network-storage.nix
{
  networkStorageInfo = {
    YourMacBook = {
      client.samba = {
        enable = true;
        mounts = [
          {
            share = "//nas.example.com/media";
            mountPoint = "/Volumes/nas-media";
            credentials = config.sops.secrets."smb-nas-credentials".path;
            options = [];  # Reserved for future use
          }
          {
            share = "//192.168.1.100/backup";
            mountPoint = "/Volumes/nas-backup";
            credentials = config.sops.secrets."smb-nas-credentials".path;
          }
        ];
      };
    };
  };
}
```

#### Step 3: Configure Credentials with SOPS

**Add secret to sops file** (e.g., `secrets/YourMacBook.yaml`):
```yaml
smb-nas-credentials: |
  username=myuser
  password=mypassword
```

**Credential file format**:
```
username=myuser
password=mypassword
```

**Important**: The credentials file uses Linux `mount.cifs` format. The Darwin module automatically parses this and converts it to the macOS URL format (`//user:pass@server/share`).

### Darwin Module Options

#### `networkStorage.client.samba.enable`
- **Type**: Boolean
- **Default**: `false`
- **Description**: Enable Samba client mounts from nix-secrets on Darwin

#### `networkStorage.client.samba.healthCheckInterval`
- **Type**: Integer (seconds)
- **Default**: `300` (5 minutes)
- **Description**: Health check interval. Set to `0` to disable health checks
- **Example**: `healthCheckInterval = 600;  # 10 minutes`

#### `networkStorage.client.samba.extraOptions`
- **Type**: List of strings
- **Default**: `[]`
- **Description**: Additional mount options (reserved for future use)

### Darwin Mount Script Logic

The mount script implements intelligent mounting with multiple safeguards:

```
1. Check if already mounted
   ├─ Yes → Test health (timeout 5s)
   │        ├─ Healthy → Exit (nothing to do)
   │        └─ Stale → Force unmount
   └─ No → Continue

2. Connectivity check (nc -z server:445)
   ├─ Port reachable → Continue
   └─ Port unreachable → Exit (fast fail)

3. Parse credentials file
   └─ Convert to URL format

4. Create mount point (mkdir -p)

5. Retry loop (max 3 attempts)
   ├─ Attempt mount
   ├─ On failure:
   │  ├─ Wait 10 seconds
   │  └─ Re-check connectivity
   └─ On success: Exit

6. Silent failure (exit 0)
```

**Key Features**:
- ✅ **Fast failure**: 5-second connectivity check before mount attempts
- ✅ **Stale mount cleanup**: Automatically removes unhealthy mounts
- ✅ **Smart retry**: Re-checks connectivity between retries
- ✅ **Graceful degradation**: Falls back if `nc` command unavailable
- ✅ **Silent failure**: Non-blocking startup (nofail behavior)

### Darwin Log Files

Mount and health check activities are logged to `/var/log/`:

```bash
# Mount agent logs
/var/log/mount-smb-{name}.log    # Standard output
/var/log/mount-smb-{name}.err    # Error output

# Health check logs
/var/log/smb-health-{name}.log

# View all logs in real-time
tail -f /var/log/mount-smb-*.log /var/log/smb-health-*.log
```

### Darwin Troubleshooting

#### Check launchd Agent Status

```bash
# List all SMB-related agents
launchctl list | grep smb

# Check specific agent
launchctl list | grep mount-smb-nas-media
```

#### Manually Trigger Mount

```bash
# Trigger mount agent
launchctl kickstart -k gui/$(id -u)/org.nixos.mount-smb-nas-media

# Trigger health check
launchctl kickstart -k gui/$(id -u)/org.nixos.smb-health-nas-media
```

#### Test Connectivity

```bash
# Test SMB port (445) connectivity
nc -z -w 5 nas.example.com 445

# Test with timeout
echo $?  # 0 = success, 1 = failure
```

#### View Agent Definition

```bash
# Find the plist file
ls -la ~/Library/LaunchAgents/org.nixos.mount-smb-*

# View plist contents
plutil -p ~/Library/LaunchAgents/org.nixos.mount-smb-nas-media.plist
```

#### Manual Mount Test

```bash
# Read credentials
cat /run/secrets/smb-nas-credentials

# Test mount manually
mkdir -p /Volumes/test-mount
mount_smbfs //user:pass@nas.example.com/media /Volumes/test-mount
```

#### Common Issues

**Issue**: Mount agent not starting
- **Check**: Verify the agent is loaded: `launchctl list | grep mount-smb`
- **Solution**: Reload configuration: `darwin-rebuild switch --flake .#YourMacBook`

**Issue**: Credentials not working
- **Check**: Verify sops secret is accessible: `cat /run/secrets/smb-nas-credentials`
- **Solution**: Ensure sops keys are properly configured

**Issue**: Mount point permissions denied
- **Check**: Verify mount point is under `/Volumes/`
- **Solution**: Darwin restricts mounting outside `/Volumes/` without special permissions

**Issue**: Network changes not triggering mount
- **Check**: Verify `WatchPaths` are being monitored in logs
- **Solution**: Adjust `ThrottleInterval` if triggers are being suppressed

**Issue**: Health check too frequent/infrequent
- **Solution**: Adjust `networkStorage.client.samba.healthCheckInterval` in config

### Darwin vs NixOS Migration

If migrating from NixOS to Darwin (or vice versa), no changes to `nix-secrets` are required. The same configuration structure works on both platforms:

```nix
# This works on BOTH NixOS and Darwin!
client.samba = {
  enable = true;
  servers = {
    nas-media = {
      mounts = [
        {
          share = "//nas.example.com/media";
          mountPoint = "/Volumes/nas-media";
        }
      ];
    };
  };
};
```

**Only difference**: Mount point convention
- NixOS: `/mnt/` or `/mount/`
- Darwin: `/Volumes/`

### Darwin Advanced Configuration

#### Customize Health Check Interval

```nix
# hosts/common/optional/autofs-darwin.nix
{
  networkStorage.client.samba = {
    healthCheckInterval = 600;  # 10 minutes instead of 5
  };
}
```

#### Disable Health Checks

```nix
{
  networkStorage.client.samba = {
    healthCheckInterval = 0;  # Disable health checks
  };
}
```

#### Multiple Mounts with Different Credentials

```nix
# nix-secrets/nix/network-storage.nix
{
  networkStorageInfo.YourMacBook = {
    client.samba = {
      enable = true;
      mounts = [
        {
          share = "//nas1.local/media";
          mountPoint = "/Volumes/nas1-media";
          credentials = config.sops.secrets."nas1-creds".path;
        }
        {
          share = "//nas2.local/backup";
          mountPoint = "/Volumes/nas2-backup";
          credentials = config.sops.secrets."nas2-creds".path;
        }
      ];
    };
  };
}
```

## Related Documentation

- [NFS exports(5)](https://linux.die.net/man/5/exports)
- [Samba smb.conf(5)](https://www.samba.org/samba/docs/current/man-html/smb.conf.5.html)
- [NixOS NFS Options](https://search.nixos.org/options?query=services.nfs.server)
- [NixOS Samba Options](https://search.nixos.org/options?query=services.samba)
- [macOS mount_smbfs(8)](https://ss64.com/osx/mount_smbfs.html)
- [launchd.plist(5)](https://www.manpagez.com/man/5/launchd.plist/)
