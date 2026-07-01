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
    # Real IP from nix-secrets; spawn.sh may still override with --hostname.
    hostname = inputs.nix-secrets.networkInfo.hosts.${host}.ip4 or host;
    # Root SSH is disabled (PermitRootLogin no); log in as the primary user and
    # let deploy-rs sudo to activate. `-A` forwards the SSH agent so the remote
    # sudo can authenticate via pam_ssh_agent_auth (passwordless).
    sshUser = nixosConfigurations.${host}.config.hostSpec.username;
    sshOpts = [
      "-A"
      "-o"
      "StrictHostKeyChecking=accept-new"
    ];
    # Build on the target host. The control machine is aarch64-darwin and the
    # local x86_64-linux builder (nix-vz-builder) has been unreliable on kernel
    # module builds; remote build sidesteps it. Override per-invocation with
    # `--remote-build false` if you want to build locally.
    remoteBuild = true;
    profiles.system = {
      user = "root";
      path = (activationLib host).activate.nixos nixosConfigurations.${host};
    };
  });
}
