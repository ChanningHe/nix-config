# EasyTier Multi-Instance VPN Configuration

## Overview
Multi-host NixOS configuration for EasyTier VPN service with support for multiple VPN instances per host.

## Design Decision: Security Model

**Chosen: Shared Secrets (方案 C)**
- All VPN credentials stored in `nix-secrets/secrets/shared.yaml`
- Trade-off: Simplicity and DRY principle over per-host secret isolation
- Risk acceptance: Single host compromise exposes all VPN credentials
- Rationale: Pragmatic approach for trusted internal network environment

**Rejected alternatives:**
- 方案 A (Per-host secrets): Maximum security but configuration duplication
- 方案 B (Hybrid): Non-sensitive shared, secrets per-host - unnecessary complexity for current threat model

## Data Structure Design

### 1. Network Configuration (nix-secrets/nix/network.nix)

```nix
{
  networkInfo = {
    hosts = {
      hostname = {
        # ... existing fields (ip4, gateway4, dns, etc.) ...
        
        easytier = {
          instance_name = {
            ipv4 = "10.144.144.x/24";  # Full CIDR notation
            # Optionally override defaults from shared config
            extraPeers = [];  # Additional peers specific to this host
          };
        };
      };
    };
  };
}
```

**Key design principles:**
- Flat attribute set: `easytier.instance_name = { config }`
- No unnecessary nesting or special cases
- Optional field: Hosts without easytier simply omit this section
- Full CIDR specification per instance (no assumptions about /24)

### 2. Shared Secrets (nix-secrets/secrets/shared.yaml)

```yaml
easytier:
  instance_name:
    network_name: ENC[...]
    network_secret: ENC[...]
    peers:
      - ENC[tcp://public.easytier.cn:11010]
      - ENC[wss://example.com:443]
```

**Key design principles:**
- Hierarchical: `easytier -> instance_name -> {name, secret, peers[]}`
- YAML arrays for peers (sops-nix supports array decryption to Nix lists)
- All instances defined once, reused across all hosts
- Hosts can append extraPeers from network.nix (unencrypted, host-specific peers)

### 3. Service Module (nix-config/hosts/common/optional/services/easytier.nix)

**Behavior:**
- Auto-generate configuration for any host with `networkInfo.hosts.<hostname>.easytier` defined
- No configuration generated if easytier field is absent (no special cases)
- Per-instance TUN device naming: `tun-${instanceName}`
- Merge peers: `shared.yaml peers ++ network.nix extraPeers`

**extraSettings customization:**
- Default: `dev_name = "tun-${instanceName}"`
- Override: Each host can extend via `services.easytier.instances.<name>.extraSettings`
- No sensitive data in extraSettings (put in host-specific configuration)

## Implementation Requirements

### Files to Create:
1. `nix-config/hosts/common/optional/services/easytier.nix` - Service module

### Files to Modify:
1. `nix-secrets/nix/network.nix` - Add easytier field to hosts
2. `nix-secrets/secrets/shared.yaml` - Add easytier instance secrets
3. Host configuration files - Import easytier module when needed

## Configuration Parameters

### Per-Instance (network.nix):
- `ipv4`: Full CIDR (e.g., "10.144.144.1/24")
- `extraPeers`: Optional list of host-specific peer addresses (unencrypted)

### Shared Secrets (shared.yaml):
- `network_name`: VPN network identifier
- `network_secret`: Pre-shared key for network authentication
- `peers`: List of initial peer addresses

### Host-Level Overrides:
- `services.easytier.instances.<name>.extraSettings`: Any additional flags
- Example: `{ flags = { enable_encryption = true; }; }`

## Security Considerations

### Current Threat Model:
- Trusted internal network environment
- Physical security assumed
- Single host compromise = VPN credential exposure (accepted risk)

### No Firewall Management:
- Module does NOT automatically open firewall ports
- Each host manages its own firewall rules based on network topology
- Default easytier port: UDP 11010 (if needed as peer node)

## Usage Example

### 1. Define Network Topology (nix-secrets/nix/network.nix):
```nix
hosts = {
  Poecilia = {
    ip4 = "10.1.10.8";
    # ... other fields ...
    easytier = {
      main = {
        ipv4 = "10.144.144.1/24";
      };
      work = {
        ipv4 = "10.145.145.1/24";
        extraPeers = ["tcp://10.1.10.100:11010"];  # Local peer
      };
    };
  };
}
```

### 2. Add Secrets (nix-secrets/secrets/shared.yaml):
```yaml
easytier:
  main:
    network_name: my-home-vpn
    network_secret: super-secret-key
    peers:
      - tcp://public.easytier.cn:11010
  work:
    network_name: work-vpn
    network_secret: another-secret
    peers:
      - wss://work.example.com:443
```

### 3. Enable on Host (nix-config/hosts/nixos/Poecilia/default.nix):
```nix
{
  imports = [
    # ...
    "hosts/common/optional/services/easytier.nix"
  ];
  
  # Optional: host-specific extra settings
  services.easytier.instances.main.extraSettings = {
    flags = {
      enable_encryption = true;
    };
  };
}
```

## Technical Implementation Notes

### SOPS Integration:
- Secrets path: `/run/secrets/easytier/<instance_name>/{network_name,network_secret,peers}`
- Source file: `${sopsFolder}/shared.yaml`
- YAML array decryption: peers array → Nix list (sops-nix native support)

### Network Device Naming:
- Auto-generated: `tun-${instanceName}`
- Ensures unique TUN devices when multiple instances exist
- Example: `main` → `tun-main`, `work` → `tun-work`

### Configuration Merging:
- Base peers from shared.yaml (encrypted)
- Additional peers from network.nix extraPeers (unencrypted)
- Final peers list = shared.peers ++ host.extraPeers

## Future Enhancements (Not Implemented)

- Per-host secret isolation (方案 A/B)
- Automatic firewall rule management
- Dynamic peer discovery
- Health check monitoring
- Metrics exporter integration

---

**Last Updated:** 2025-10-06
**Status:** Design finalized, ready for implementation