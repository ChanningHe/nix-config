{
  description = "ChanningHe's Nix-Config Starter";
  outputs =
    {
      self,
      nixpkgs,
      nix-darwin,
      ...
    }@inputs:
    let
      inherit (self) outputs;

      #
      # ========= Architectures =========
      #
      # NOTE(starter): Comment or uncomment architectures below as required by your hosts.
      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-darwin"
      ];

      # ========== Extend lib with lib.custom ==========
      # NOTE: This approach allows lib.custom to propagate into hm
      # see: https://github.com/nix-community/home-manager/pull/3454
      lib = nixpkgs.lib.extend (self: super: { custom = import ./lib { inherit (nixpkgs) lib; }; });

    in
    {
      #
      # ========= Overlays =========
      #
      # Custom modifications/overrides to upstream packages
      overlays = import ./overlays { inherit inputs; };

      #
      # ========= Host Configurations =========
      #
      # Building configurations is available through `just rebuild` or `nixos-rebuild --flake .#hostname`
      nixosConfigurations = builtins.listToAttrs (
        map (host: {
          name = host;
          value = nixpkgs.lib.nixosSystem {
            specialArgs = {
              inherit inputs outputs lib;
              isDarwin = false;
            };
            modules = [ ./hosts/nixos/${host} ];
          };
        }) (builtins.attrNames (builtins.readDir ./hosts/nixos))
      );

      darwinConfigurations = builtins.listToAttrs (
        map (host: {
          name = host;
          value = nix-darwin.lib.darwinSystem {
            specialArgs = {
              inherit inputs outputs lib;
              isDarwin = true;
            };
            modules = [ ./hosts/darwin/${host} ];
          };
        }) (builtins.attrNames (builtins.readDir ./hosts/darwin))
      );

      #
      # ========= Packages =========
      #
      # Expose custom packages

      /*
        NOTE: This is only for exposing packages exterally; ie, `nix build .#packages.x86_64-linux.cd-gitroot`
        For internal use, these packages are added through the default overlay in `overlays/default.nix`
      */

      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ self.overlays.default ];
          };
        in
        nixpkgs.lib.packagesFromDirectoryRecursive {
          callPackage = nixpkgs.lib.callPackageWith pkgs;
          directory = ./pkgs/common;
        }
      );

      #
      # ========= Formatting =========
      #
      # Nix formatter available through 'nix fmt' https://github.com/NixOS/nixfmt
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);
      # Pre-commit checks
      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        import ./checks.nix { inherit inputs system pkgs; }
      );

      #
      # ========= DevShell =========
      #
      # Custom shell for bootstrapping on new hosts, modifying nix-config, and secrets management
      devShells = forAllSystems (
        system:
        import ./shell.nix {
          pkgs = nixpkgs.legacyPackages.${system};
          checks = self.checks.${system};
        }
      );
    };

  inputs = {
    #
    # ========= Official NixOS, Nix-Darwin, and HM Package Sources =========
    #
    # NOTE(starter): As with typical flake-based configs, you'll need to update the nixOS, hm,
    # and darwin version numbers below when new releases are available.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    # nixpkgs-unstable provides packages not yet in stable, exposed via pkgs.unstable overlay.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Pinned nixpkgs-unstable commit where docker_28 = 28.5.1 + runc 1.3.0 (pre-CVE-2025-52881).
    # Used by nixos-rl to avoid runc 1.3.2+ AppArmor breakage in Proxmox LXC.
    # Remove once Proxmox host is updated to PVE 8.4.16+ (lxc-pve 6.0.5-2).
    nixpkgs-docker-compat.url = "github:NixOS/nixpkgs/d560188c88fc6dcedeee0e970472b6c8190d735d";

    # Proxmox VE virtualization platform
    proxmox-nixos.url = "github:SaumonNet/proxmox-nixos";

    hardware.url = "github:nixos/nixos-hardware";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-26.05-darwin";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
      #url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };
    # Rosetta Linux builder for Apple Silicon
    nix-rosetta-builder = {
      url = "github:cpick/nix-rosetta-builder";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };
    # Native Linux builder for Apple Silicon (Virtualization.framework,
    # external-builders): ephemeral VM per build, no SSH/store copying.
    # NOTE: intentionally NOT following nixpkgs-darwin — the guest kernel
    # and swift toolchain are tested against this flake's own lock.
    nix-vz-builder = {
      url = "github:ChanningHe/nix-vz-builder";
    };

    #
    # ========= Desktop Environment =========
    #

    # niri: scrollable-tiling Wayland compositor
    # NOTE: Do NOT follow nixpkgs — niri-flake manages its own mesa overlay for GPU compatibility
    niri.url = "github:sodiboo/niri-flake";

    # Noctalia: minimal desktop shell (bar, launcher, notifications, lock screen)
    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    #
    # ========= Applications =========
    #

    # VS Code Server for remote development
    vscode-server = {
      url = "github:nix-community/nixos-vscode-server";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Fast Zsh syntax highlighter (Rust daemon, replaces zsh-syntax-highlighting)
    zsh-patina = {
      url = "github:michel-kraemer/zsh-patina";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    #
    # ========= Utilities =========
    #
    nxv = {
      url = "github:jamesbrink/nxv";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Secrets management. See ./docs/secretsmgmt.md
    sops-nix = {
      url = "github:mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Pre-commit
    pre-commit-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    #
    # ========= Personal Repositories =========
    #
    # Private secrets repo.  See ./docs/secretsmgmt.md
    # Authenticates via ssh and use shallow clone
    # FIXME(starter): The url below points to the 'simple' branch of the public, nix-secrets-reference repository which is inherently INSECURE!
    # Replace the url with your personal, private nix-secrets repo.
    nix-secrets = {
      url = "git+ssh://git@github.com/ChanningHe/nix-secrets.git?ref=master&shallow=1";
      inputs = { };
    };
  };
}
