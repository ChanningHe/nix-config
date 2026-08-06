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
        "aarch64-linux"
      ];

      # ========== Extend lib with lib.custom ==========
      lib = nixpkgs.lib.extend (self: super: { custom = import ./lib { inherit (nixpkgs) lib; }; });

    in
    {
      #
      # ========= Overlays =========
      #
      # Custom modifications/overrides to upstream packages
      overlays = import ./overlays { inherit inputs lib; };

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
      # ========= Standalone Home Manager =========
      #
      # Generic profiles to load home/<user> on any Linux host with nix.
      # Activate via `just home`. See homes.nix.
      homeConfigurations = import ./homes.nix { inherit inputs outputs lib; };

      #
      # ========= deploy-rs nodes =========
      #
      deploy = import ./deploy.nix {
        inherit inputs lib;
        nixosConfigurations = self.nixosConfigurations;
      };

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
        lib.custom.scanPackages {
          inherit pkgs;
          root = ./pkgs;
        }
      );

      #
      # ========= Apps =========
      #
      apps = forAllSystems (system: {
        # `nix run .#deploy` — deploy-rs CLI pinned to the locked input, so it
        # matches the activation built by deploy.nix.
        deploy = {
          type = "app";
          program = "${inputs.deploy-rs.packages.${system}.default}/bin/deploy";
        };
        # `nix run .#home-manager` — home-manager CLI pinned to the locked
        # input, so standalone activation matches the homeConfigurations above.
        home-manager = {
          type = "app";
          program = "${inputs.home-manager.packages.${system}.default}/bin/home-manager";
        };
      });

      #
      # ========= Formatting =========
      #
      # Nix formatter available through 'nix fmt' https://github.com/NixOS/nixfmt
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt);
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
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Pinned nixpkgs-unstable commit where docker_28 = 28.5.1 + runc 1.3.0 (pre-CVE-2025-52881).
    # Used by nixos-rl to avoid runc 1.3.2+ AppArmor breakage in Proxmox LXC.
    # Remove once Proxmox host is updated to PVE 8.4.16+ (lxc-pve 6.0.5-2).
    nixpkgs-docker-compat.url = "github:NixOS/nixpkgs/d560188c88fc6dcedeee0e970472b6c8190d735d";

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

    systems-linux.url = "github:nix-systems/default-linux";

    nix-vz-builder = {
      url = "github:ChanningHe/nix-vz-builder";
    };

    proxmox-nixos.url = "github:SaumonNet/proxmox-nixos";

    niri.url = "github:sodiboo/niri-flake";

    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zsh-patina = {
      url = "github:michel-kraemer/zsh-patina";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Bash loadable builtin replacing readline: inline autosuggestions,
    # fuzzy tab completion, syntax highlighting, fuzzy Ctrl+R.
    # Pinned to the release tag: master (post-#879/#881 viewport rework)
    # regressed double-width chars — typing CJK loops the renderer.
    flyline = {
      url = "github:HalFrgrd/flyline/v1.5.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nxv = {
      url = "github:utensils/nxv";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-facter-modules.url = "github:nix-community/nixos-facter-modules";

    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pre-commit-hooks = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    #
    # ========= Personal Repositories =========
    #
    # Private secrets repo.
    # Authenticates via ssh and use shallow clone
    nix-secrets = {
      url = "git+ssh://git@github.com/ChanningHe/nix-secrets.git?ref=master&shallow=1";
      inputs = { };
    };
  };
}
