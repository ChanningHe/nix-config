# Nix-Config Modular Framework Architecture
> Supports both NixOS and Darwin (macOS) with platform-agnostic design

## System Architecture Overview

```mermaid
graph TD
    subgraph "Flake Layer"
        flake[flake.nix<br />Root Configuration]
    end
    
    subgraph "Core System"
        lib[lib.custom]
        overlays[Overlays]
        packages[Custom Packages]
    end
    
    subgraph "Configuration & Modules"
        direction LR
        
        subgraph "Configuration Layers"
            direction TB
            Layer1[Core System<br />hosts/common/core/]
            Layer2[Optional Services<br />hosts/common/optional/]
            Layer3[User Specific<br />hosts/common/users/]
            Layer4[Host Specific<br />hosts/nixos/hostname/]
        end
        
        subgraph "Module System"
            direction TB
            host-spec[host-spec.nix]
            common-modules[Common Modules]
            nixos-modules[NixOS Modules]
            darwin-modules[Darwin Modules]
            home-manager-config[Home Manager]
        end
    end
    
    subgraph "Host Configurations"
        direction TB
        subgraph "NixOS Hosts"
            iso[ISO Installer]
            tester[Config Tester]
            poecilia[Poecilia]
            pseudomugil[Pseudomugil]
        end
        subgraph "Darwin Hosts"
            macbook[ChanningdeMacBook-Pro]
        end
    end
    
    subgraph "Flake Inputs"
        nixpkgs[Nixpkgs 25.05]
        nixpkgs-darwin[Nixpkgs Darwin 25.05]
        nix-darwin[Nix-Darwin 25.05]
        home-manager[Home Manager 25.05]
        sops-nix[Sops-nix]
        disko[Disko]
        nix-secrets[Nix-secrets]
    end

    %% Connections
    flake --> lib
    flake --> overlays
    flake --> packages
    flake --> Layer1
    flake --> host-spec
    
    Layer1 --> Layer2
    Layer2 --> Layer3
    Layer3 --> Layer4
    
    host-spec --> common-modules
    common-modules --> nixos-modules
    common-modules --> darwin-modules
    common-modules --> home-manager-config
    
    Layer4 --> iso
    Layer4 --> tester
    Layer4 --> poecilia
    Layer4 --> pseudomugil
    Layer4 --> macbook
    
    nixpkgs --> flake
    nixpkgs-darwin --> flake
    nix-darwin --> flake
    home-manager --> flake
    sops-nix --> flake
    disko --> flake
    nix-secrets --> flake

    classDef systemLayer stroke:#01579b,stroke-width:2px
    classDef configLayer stroke:#4a148c,stroke-width:2px
    classDef moduleLayer stroke:#1b5e20,stroke-width:2px
    classDef hostLayer stroke:#880e4f,stroke-width:2px
    classDef darwinLayer stroke:#e65100,stroke-width:2px
    classDef inputLayer stroke:#00838f,stroke-width:2px
    classDef neutral stroke:#616161,stroke-width:2px
    
    class flake systemLayer
    class lib,overlays,packages systemLayer
    class Layer1,Layer2,Layer3,Layer4 configLayer
    class host-spec,common-modules,nixos-modules,darwin-modules,home-manager-config moduleLayer
    class iso,tester,poecilia,pseudomugil hostLayer
    class macbook darwinLayer
    class nixpkgs,nixpkgs-darwin,nix-darwin,home-manager,sops-nix,disko,nix-secrets inputLayer
```

## Configuration Inheritance Hierarchy

```mermaid
graph TD
    subgraph "Configuration Inheritance"
        Root[Root Configuration<br />flake.nix]
        
        subgraph "Common Base"
            CommonCore[Common Core<br />hosts/common/core/]
            CommonOptional[Common Optional<br />hosts/common/optional/]
            CommonUsers[Common Users<br />hosts/common/users/]
        end
        
        subgraph "Platform Specific"
            NixOSBase[NixOS Base<br />hosts/nixos/common/]
            DarwinBase[Darwin Base<br />hosts/darwin/common/]
        end
        
        subgraph "Host Specific"
            HostConfig[Host Configuration<br />hosts/nixos/hostname/]
            Hardware[Hardware Config<br />hardware-configuration.nix]
        end
        
        subgraph "User Environment"
            HomeManager[Home Manager<br />home-manager]
            UserConfig[User Config<br />home/username/]
        end
    end

    Root --> CommonCore
    CommonCore --> CommonOptional
    CommonOptional --> CommonUsers
    CommonUsers --> NixOSBase
    NixOSBase --> HostConfig
    HostConfig --> Hardware
    
    CommonCore --> HomeManager
    HomeManager --> UserConfig
    
    classDef base stroke:#e65100,stroke-width:2px
    classDef platform stroke:#0d47a1,stroke-width:2px
    classDef host stroke:#880e4f,stroke-width:2px
    classDef user stroke:#33691e,stroke-width:2px
    classDef neutral stroke:#616161,stroke-width:2px
    
    class CommonCore,CommonOptional,CommonUsers base
    class NixOSBase,DarwinBase platform
    class HostConfig,Hardware host
    class HomeManager,UserConfig user
    class Root neutral
```

## Module Loading Flow

```mermaid
sequenceDiagram
    participant Flake as flake.nix
    participant Host as Host Config
    participant Common as Common Modules
    participant Platform as Platform Modules
    participant User as User Config
    
    Flake->>Host: Load host-specific configuration
    Host->>Common: Import common core modules
    Common->>Platform: Load platform-specific modules
    Platform->>User: Apply user environment
    
    Note over Common: hosts/common/core/default.nix
    Note over Platform: hosts/nixos/hostname/
    Note over User: home/username/common/
```

## Data Flow Diagram

```mermaid
graph LR
    subgraph "Data Sources"
        Secrets[nix-secrets]
        HostSpec[hostSpec Module]
        Hardware[Hardware Config]
    end
    
    subgraph "Configuration Processing"
        Flake[Flake Processing]
        Modules[Module System]
        Overlays[Overlays]
    end
    
    subgraph "Final Configuration"
        NixOS[NixOS System]
        HomeManager[Home Manager]
        Packages[Custom Packages]
    end
    
    Secrets -->|domain, email, networking| HostSpec
    HostSpec -->|user config| Flake
    Hardware -->|system specs| Flake
    
    Flake --> Modules
    Modules --> Overlays
    
    Modules --> NixOS
    Modules --> HomeManager
    Overlays --> Packages
    
    classDef dataSource stroke:#6a1b9a,stroke-width:2px
    classDef processing stroke:#00695c,stroke-width:2px
    classDef finalConfig stroke:#c62828,stroke-width:2px
    classDef neutral stroke:#616161,stroke-width:2px
    
    class Secrets,HostSpec,Hardware dataSource
    class Flake,Modules,Overlays processing
    class NixOS,HomeManager,Packages finalConfig
```

## Key Directory Structure

```
nix-config/
├── hosts/                        # Host configurations
│   ├── common/                   # Common configurations
│   │   ├── core/                 # Core system configuration
│   │   │   ├── default.nix      # Platform-agnostic core
│   │   │   ├── nixos.nix        # NixOS-specific core
│   │   │   ├── darwin.nix       # Darwin-specific core
│   │   │   └── sops.nix         # Secrets management
│   │   ├── optional/             # Optional services
│   │   └── users/                # User configurations
│   │       └── channinghe/       
│   │           ├── default.nix   # Platform-agnostic user config
│   │           ├── nixos.nix     # NixOS-specific user config
│   │           └── darwin.nix    # Darwin-specific user config
│   ├── nixos/                    # NixOS specific hosts
│   │   ├── poecilia/
│   │   ├── pseudomugil/
│   │   ├── iso/                  # ISO installer
│   │   └── tester/               # Config tester
│   └── darwin/                   # Darwin specific hosts
│       └── ChanningdeMacBook-Pro/
├── home/                         # Home Manager configurations
│   └── channinghe/               # User-specific configurations
│       ├── common/
│       │   ├── core/             # Core user modules
│       │   │   ├── default.nix   # Platform-agnostic
│       │   │   ├── nixos.nix     # NixOS-specific
│       │   │   ├── darwin.nix    # Darwin-specific
│       │   │   └── zsh.nix       # Zsh configuration
│       │   ├── dotfiles/         # Configuration files
│       │   │   └── p10k.zsh      # Powerlevel10k config
│       │   └── optional/         # Optional user modules
│       │       └── ssh-agent.nix # SSH agent management
│       ├── poecilia.nix          # Host-specific HM config
│       └── ChanningdeMacBook-Pro.nix
├── modules/                      # Reusable modules
│   ├── common/                   # Common modules
│   │   └── host-spec.nix         # Host specification module
│   ├── hosts/                    # Host modules
│   └── home/                     # Home Manager modules
├── overlays/                     # Package overlays
├── pkgs/                         # Custom packages
├── lib/                          # Custom library functions
└── scripts/                      # Helper scripts
    ├── rebuild.sh                # Platform-aware rebuild
    └── check-sops.sh             # SOPS verification
```

## Quick Reference

| Layer | Path | Purpose | Platform |
|-------|------|---------|----------|
| Core | `hosts/common/core/default.nix` | System-wide settings | Both |
| Core | `hosts/common/core/nixos.nix` | NixOS-specific settings | NixOS |
| Core | `hosts/common/core/darwin.nix` | Darwin-specific settings | Darwin |
| Optional | `hosts/common/optional/` | Optional services | Both |
| Users | `hosts/common/users/*/default.nix` | User configurations | Both |
| Users | `hosts/common/users/*/nixos.nix` | User NixOS config | NixOS |
| Users | `hosts/common/users/*/darwin.nix` | User Darwin config | Darwin |
| Host | `hosts/nixos/*/default.nix` | NixOS host setup | NixOS |
| Host | `hosts/darwin/*/default.nix` | Darwin host setup | Darwin |
| Home | `home/*/common/core/` | User environment modules | Both |
| Home | `home/*/common/dotfiles/` | Configuration files | Both |

## Layered Architecture

```mermaid
graph TD
    subgraph "Configuration Layers"
        Layer1["Layer 1: Core System<br />hosts/common/core/"]
        Layer2["Layer 2: Optional Services<br />hosts/common/optional/"]
        Layer3["Layer 3: User Specific<br />hosts/common/users/"]
        Layer4["Layer 4: Host Specific<br />hosts/nixos/hostname/"]
    end
    
    Layer1 --> Layer2
    Layer2 --> Layer3
    Layer3 --> Layer4
    
    classDef base stroke:#e65100,stroke-width:2px
    classDef optional stroke:#7b1fa2,stroke-width:2px
    classDef user stroke:#33691e,stroke-width:2px
    classDef host stroke:#880e4f,stroke-width:2px
    classDef neutral stroke:#616161,stroke-width:2px
    
    class Layer1 base
    class Layer2 optional
    class Layer3 user
    class Layer4 host
```

## Platform-Specific Modular Design Pattern

### Design Philosophy

The configuration uses a **three-file pattern** for platform-agnostic design:

```mermaid
graph LR
    subgraph "Module Pattern"
        Default[default.nix<br />Platform-agnostic<br />Common logic]
        NixOS[nixos.nix<br />Linux-specific<br />systemd, NetworkManager]
        Darwin[darwin.nix<br />macOS-specific<br />nix-darwin, launchd]
    end
    
    Default -->|lib.mkDefault| NixOS
    Default -->|lib.mkDefault| Darwin
    
    classDef common stroke:#2e7d32,stroke-width:2px
    classDef linux stroke:#1565c0,stroke-width:2px
    classDef macos stroke:#ef6c00,stroke-width:2px
    classDef neutral stroke:#616161,stroke-width:2px
    
    class Default common
    class NixOS linux
    class Darwin macos
```

### Key Principles

1. **Platform-Agnostic Base (`default.nix`)**
   - Use `lib.mkDefault` for values that can be overridden
   - Only include truly cross-platform logic
   - Example: User name, shell (with mkDefault), SSH keys

2. **Platform-Specific Extensions**
   - `nixos.nix` - Linux-only packages (ethtool, systemd)
   - `darwin.nix` - macOS-only settings (TouchID, Homebrew paths)

3. **Priority System**
   ```nix
   # default.nix - low priority
   shell = lib.mkDefault pkgs.bash;
   
   # darwin.nix - normal priority (overrides default)
   shell = pkgs.zsh;
   
   # If conflicts - use lib.mkForce (high priority)
   nix.registry = lib.mkForce { ... };
   ```

### Examples

#### Host-Level Configuration

```
hosts/common/core/
├── default.nix    # Nix settings, common packages
├── nixos.nix      # Linux packages, systemd
├── darwin.nix     # macOS settings, Touch ID
└── sops.nix       # Secrets (platform-aware)
```

#### User-Level Configuration

```
hosts/common/users/channinghe/
├── default.nix    # Name, SSH keys (mkDefault shell)
├── nixos.nix      # Groups, systemd tmpfiles
└── darwin.nix     # Home path, zsh shell override
```

#### Home-Manager Configuration

```
home/channinghe/common/core/
├── default.nix    # Import all modules
├── nixos.nix      # Linux-specific packages
├── darwin.nix     # macOS-specific packages
├── zsh.nix        # Shell config (platform-agnostic)
└── ../dotfiles/   # Config files (p10k.zsh)
```

### Platform Detection

The framework uses `hostSpec.isDarwin` and `pkgs.stdenv` for platform detection:

```nix
# Method 1: Using hostSpec
lib.mkIf (!config.hostSpec.isDarwin) {
  # NixOS-only config
}

# Method 2: Using pkgs.stdenv
lib.optionalAttrs pkgs.stdenv.isLinux {
  # Linux-only config
}

# Method 3: File-level separation
# hosts/common/core/default.nix imports:
../users/${username}/default.nix  # Always
../users/${username}/nixos.nix    # Only on NixOS
../users/${username}/darwin.nix   # Only on Darwin
```

### Common Pitfalls and Solutions

| Issue | Problem | Solution |
|-------|---------|----------|
| Option conflicts | Same option defined twice | Use `lib.mkDefault` in base |
| Missing group | Darwin users don't have `group` | Use `lib.optionalAttrs` |
| Wrong stateVersion | String vs Int | NixOS=string, Darwin=int |
| Auto-optimise-store | Corrupts on Darwin | Use `nix.optimise.automatic` |
| SOPS paths | Different SSH key paths | Conditional `sshKeyPaths` |
