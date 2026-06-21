# Activates NVIDIA vGPU on the current host.
{ config, lib, ... }:
let
  vgpu = config.hostSpec.serviceInfo.nvidiaVgpu or { };
in
{
  assertions = [
    {
      assertion = (vgpu.driverUrl or "") != "" && (vgpu.driverSha256 or "") != "";
      message = ''
        nvidia-vgpu.nix is imported but serviceInfo.nvidiaVgpu is incomplete.
        Set version, driverUrl and driverSha256 in nix-secrets/nix/services.nix.
      '';
    }
  ];

  hardware.nvidia.vgpu = {
    enable = true;
    version = lib.mkDefault (vgpu.version or "");
    driverUrl = lib.mkDefault (vgpu.driverUrl or "");
    driverSha256 = lib.mkDefault (vgpu.driverSha256 or "");
  };
}
