# Rosetta Linux Builder for Apple Silicon
#
# Enables x86_64-linux builds on aarch64-darwin using Rosetta 2 translation.
# This provides a local Linux builder without requiring a remote machine.
#
# Requirements:
# - Apple Silicon Mac (M1/M2/M3)
# - Rosetta 2 installed (softwareupdate --install-rosetta)
#
# Bootstrap Process:
# 1. First run: set `bootstrap = true` and run `darwin-rebuild switch`
#    This uses nix-darwin's built-in linux-builder (QEMU) to build rosetta-builder
# 2. After successful build: set `bootstrap = false` and run `darwin-rebuild switch` again
#    This switches to the faster rosetta-builder

{ inputs, ... }:
{
  imports = [
    inputs.nix-rosetta-builder.darwinModules.default
  ];

  nix-rosetta-builder = {
    onDemand = true;
    diskSize = "60GiB";
  };
}
