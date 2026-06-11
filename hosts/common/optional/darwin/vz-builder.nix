# Native Linux Builder for Apple Silicon (nix-vz-builder)
#
# Realises aarch64-linux and x86_64-linux derivations in ephemeral
# Virtualization.framework VMs via the `external-builders` experimental
# feature: sub-second VM per build, host store shared over virtiofs,
# no SSH keys, no store copying, no long-running VM state.
# x86_64-linux runs through Rosetta 2 (softwareupdate --install-rosetta).
#
# Replaces both nix-darwin's linux-builder (QEMU) and rosetta-builder
# (Lima): no bootstrap step, the host CLI and guest kernel/initramfs are
# built by the flake (everything Linux comes from the binary cache).

{ inputs, ... }:
{
  imports = [
    inputs.nix-vz-builder.darwinModules.default
  ];

  programs.nix-vz-builder = {
    enable = true;
    cpus = 6;
    memoryBytes = 12 * 1024 * 1024 * 1024;
    # debug = true;                # kernel boot messages in build logs
  };
}
