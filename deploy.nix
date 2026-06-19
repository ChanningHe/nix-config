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
    profiles.system = {
      user = "root";
      path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos nixosConfigurations.${host};
    };
  });
}
