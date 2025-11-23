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

        # Samba Client
        samba = {
          enable = true;  # Enable flag
          mounts = [
            {
              share = "//nas.local/media";
              mountPoint = "/mnt/nas-media";
              credentials = "/root/.smbcredentials";
              options = [ "ro" "uid=1000" ];
            }
          ];
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

## Related Documentation

- [NFS exports(5)](https://linux.die.net/man/5/exports)
- [Samba smb.conf(5)](https://www.samba.org/samba/docs/current/man-html/smb.conf.5.html)
- [NixOS NFS Options](https://search.nixos.org/options?query=services.nfs.server)
- [NixOS Samba Options](https://search.nixos.org/options?query=services.samba)
