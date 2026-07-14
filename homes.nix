# Standalone home-manager configurations.
#
# Generic profiles to load home/<user> on any Linux host with nix, without
# defining a fleet host. Activate via `just home` or:
#   home-manager switch --flake .#channinghe@x86_64-linux -b bk
{
  inputs,
  outputs,
  lib,
}:
let
  mkHome =
    username: system:
    inputs.home-manager.lib.homeManagerConfiguration {
      # The lib extended with lib.custom (relativeToRoot, scanPaths),
      # matching what hosts pass through specialArgs.
      inherit lib;
      pkgs = import inputs.nixpkgs {
        inherit system;
        overlays = [ outputs.overlays.default ];
        config.allowUnfree = true;
      };
      extraSpecialArgs = {
        inherit inputs;
        # Full hostSpec, populated the same way hosts/common/core does,
        # so home modules behave identically to fleet hosts.
        hostSpec = {
          inherit username;
          hostName = "generic";
          # Read directly off this attrset (not via the option's default) by
          # home/*/common/core/default.nix to pick the platform import.
          isDarwin = false;
          inherit (inputs.nix-secrets)
            domain
            email
            userFullName
            networking
            networkInfo
            serviceInfo
            ;
        };
      };
      modules = [ ./home/${username}/generic.nix ];
    };
in
{
  "channinghe@x86_64-linux" = mkHome "channinghe" "x86_64-linux";
  "channinghe@aarch64-linux" = mkHome "channinghe" "aarch64-linux";
}
