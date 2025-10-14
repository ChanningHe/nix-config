# NixOS Modular Framework Architecture

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
        iso[ISO Installer]
        tester[NixOS Config Tester]
        poecilia[Poecilia]
        pseudomugil[Pseudomugil]
        darwin-hosts[Darwin Hosts<br />Currently Disabled]
    end
    
    subgraph "Flake Inputs"
        nixpkgs[Nixpkgs 25.05]
        home-manager[Home Manager]
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
    Layer4 --> darwin-hosts
    
    nixpkgs --> flake
    home-manager --> flake
    sops-nix --> flake
    disko --> flake
    nix-secrets --> flake

    classDef systemLayer fill:#e1f5fe,stroke:#01579b
    classDef configLayer fill:#f3e5f5,stroke:#4a148c
    classDef moduleLayer fill:#e8f5e8,stroke:#1b5e20
    classDef hostLayer fill:#fce4ec,stroke:#880e4f
    
    class flake systemLayer
    class lib,overlays,packages systemLayer
    class Layer1,Layer2,Layer3,Layer4 configLayer
    class host-spec,common-modules,nixos-modules,darwin-modules,home-manager-config moduleLayer
    class iso,tester,poecilia,pseudomugil,darwin-hosts hostLayer
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
    
    classDef base fill:#fff3e0,stroke:#e65100
    classDef platform fill:#e3f2fd,stroke:#0d47a1
    classDef host fill:#fce4ec,stroke:#880e4f
    classDef user fill:#f1f8e9,stroke:#33691e
    
    class CommonCore,CommonOptional,CommonUsers base
    class NixOSBase,DarwinBase platform
    class HostConfig,Hardware host
    class HomeManager,UserConfig user
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
```

## Key Directory Structure

```
nix-config/
├── hosts/                    # Host configurations
│   ├── common/              # Common configurations
│   │   ├── core/            # Core system configuration
│   │   ├── optional/        # Optional services
│   │   └── users/           # User configurations
│   ├── nixos/               # NixOS specific hosts
│   └── darwin/              # Darwin specific hosts
├── home/                    # Home Manager configurations
│   └── username/            # User-specific configurations
├── modules/                 # Reusable modules
│   ├── common/              # Common modules
│   ├── hosts/               # Host modules
│   └── home/                # Home Manager modules
├── overlays/                # Package overlays
├── pkgs/                    # Custom packages
└── lib/                     # Custom library functions
```

## Quick Reference

| Layer | Path | Purpose |
|-------|------|---------|
| Core | `hosts/common/core/` | System-wide settings |
| Optional | `hosts/common/optional/` | Optional services |
| Users | `hosts/common/users/` | User configurations |
| Host | `hosts/nixos/*/default.nix` | Host-specific setup |
| Home | `home/*/common/` | User environment |

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
    
    classDef base fill:#fff3e0,stroke:#e65100
    classDef platform fill:#e3f2fd,stroke:#0d47a1
    classDef host fill:#fce4ec,stroke:#880e4f
    classDef user fill:#f1f8e9,stroke:#33691e
    
    class Layer1 base
    class Layer4 host
```
