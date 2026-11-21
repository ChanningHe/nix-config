# deploy-rs node definitions, consumed by scripts/spawn.sh (deploy step).
# Factored out of flake.nix to keep the main outputs lean.
{
  inputs,
  lib,
  nixosConfigurations,
}:
let
  # Deployable hosts: every nixos host except the live installer image.
  deployable = lib.filter (h: h != "iso") (builtins.attrNames nixosConfigurations);
  activationLib =
    host: inputs.deploy-rs.lib.${nixosConfigurations.${host}.pkgs.stdenv.hostPlatform.system};
in
{
  nodes = lib.genAttrs deployable (host: {
    # SSH target is the node name, resolved by ~/.ssh/config.
    # Override per-invocation with `--hostname <ip>`.
    hostname = host;
    # Log in as root: deploy-rs then skips sudo, whose pam_rssh check cost a
    # YubiKey touch per remote command (activate, wait, confirm).
    # Root accepts hardware keys only (users/channinghe/nixos.nix).
    sshUser = "root";
    sshOpts = [
      # Don't leave a touch-free root master socket behind (ssh.nix persists 20m)
      "-o"
      "ControlPersist=60"
      "-o"
      "StrictHostKeyChecking=accept-new"
    ];
    # Build on the target host. The control machine is aarch64-darwin and the
    # local x86_64-linux builder (nix-vz-builder) has been unreliable on kernel
    # module builds; remote build sidesteps it. Override per-invocation with
    # `--remote-build false` if you want to build locally.
    # Low-memory hosts (optional/system/low-mem.nix) never build on themselves.
    remoteBuild = !nixosConfigurations.${host}.config.hostSpec.isLowMem;
    profiles.system = {
      user = "root";
      path = (activationLib host).activate.nixos nixosConfigurations.${host};
    };
  });
}
