# NVIDIA vGPU host module (native SR-IOV, no unlock).
#
# Builds the `-vgpu-kvm.run` host driver and turns the machine into a vGPU
# provider: loads nvidia + nvidia-vgpu-vfio, runs the nvidia-vgpud/-mgr daemons
# and creates the device nodes. Targets datacenter GPUs that support vGPU
# natively (Tesla, A/L/H series), so it drops the consumer-card machinery
# (vgpu_unlock, merge/unlock patches).
#
# The host driver is a HEADLESS package: it ships only libnvidia-ml/-vgpu/-vgxcfg,
# the daemons, nvidia-smi and the kernel sources — no X driver, no GL/GLX, no
# nvidia-modeset.ko. So we do NOT use the desktop `hardware.nvidia` module (it
# wants modeset + GL); we wire the few pieces a vGPU host needs by hand.
#
# Driver location is license-gated and supplied via the options below (fed from
# nix-secrets by the optional bridge).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.nvidia.vgpu;
  version = cfg.version;

  vgpuRun = pkgs.fetchurl {
    url = cfg.driverUrl;
    sha256 = cfg.driverSha256;
  };

  # Reuse nixpkgs' nvidia-x11 derivation only for its unpack + kernel-module
  # machinery (passthru.mod builds nvidia.ko + nvidia-vgpu-vfio.ko from the .run
  # `kernel/` sources). disable32Bit drops the lib32 output the host driver can't
  # fill. The stock installPhase assumes a desktop driver, so we replace it.
  vgpuPackage =
    (config.boot.kernelPackages.nvidiaPackages.stable.override { disable32Bit = true; }).overrideAttrs
      (old: {
        name = "nvidia-x11-vgpu-${version}-${config.boot.kernelPackages.kernel.version}";
        inherit version;
        src = vgpuRun;

        postPatch = ''
          # Repoint nvidia-vgpud's hardcoded vgpuConfig.xml dir to /etc (see the
          # etc."..." entry below). This is an in-place binary edit, so the
          # replacement MUST be the SAME length as "/usr/share/nvidia/vgpu" (22
          # chars) — a shorter string makes `sed -i` shift the rest of the binary
          # left and corrupts the ELF. Hence the padding in "/etc/nvidia-vgpu-xxxxx".
          sed -i 's|/usr/share/nvidia/vgpu|/etc/nvidia-vgpu-xxxxx|' nvidia-vgpud

          substituteInPlace sriov-manage \
            --replace-fail lspci ${pkgs.pciutils}/bin/lspci \
            --replace-fail setpci ${pkgs.pciutils}/bin/setpci
        '';

        # Host-only install: just the libs, daemons, kernel sources, firmware and
        # vgpuConfig.xml. None of the desktop X/GL/ICD bits the stock phase expects.
        installPhase = ''
          runHook preInstall

          mkdir -p $out/lib
          cp -prd *.so.* $out/lib/

          mkdir -p $bin/bin
          for b in nvidia-smi nvidia-debugdump nvidia-modprobe \
                   nvidia-vgpud nvidia-vgpu-mgr nvidia-xid-logd sriov-manage; do
            if [ -e "$b" ]; then install -Dm755 "$b" "$bin/bin/$b"; fi
          done

          if [ -n "$modsrc" ]; then cp -r kernel $modsrc; fi
          if [ -n "$firmware" ]; then
            install -Dm644 -t $firmware/lib/firmware/nvidia/$version firmware/gsp*.bin
          fi
          install -Dm644 vgpuConfig.xml $out/vgpuConfig.xml

          runHook postInstall
        '';

        # Set rpaths and the ld interpreter the stock installPhase would have, and
        # build the libfoo.so -> libfoo.so.1 -> libfoo.so.VER symlink chains.
        preFixup = ''
          for so in $out/lib/*.so.*; do
            patchelf --set-rpath "$out/lib:$libPath" "$so"
            soname=$(patchelf --print-soname "$so" 2>/dev/null || true)
            bn=$(basename "$so")
            unversioned=''${bn/\.so\.[0-9.]*/.so}
            if [ -n "$soname" ] && [ "$soname" != "$bn" ]; then ln -sf "$bn" "$out/lib/$soname"; fi
            if [ -n "$soname" ] && [ "$soname" != "$unversioned" ]; then ln -sf "$soname" "$out/lib/$unversioned"; fi
          done

          for d in nvidia-vgpud nvidia-vgpu-mgr nvidia-smi nvidia-debugdump sriov-manage; do
            f="$bin/bin/$d"
            if [ -e "$f" ] && patchelf --print-interpreter "$f" >/dev/null 2>&1; then
              patchelf --interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
                --set-rpath "$out/lib:$libPath" "$f"
            fi
          done
        '';
      });

  mkVgpuDaemon =
    {
      description,
      exec,
      type,
      after ? [ ],
      requires ? [ ],
      extraServiceConfig ? { },
    }:
    {
      inherit description after requires;
      wants = [ "syslog.target" ];
      wantedBy = [ "multi-user.target" ];
      # __RM_NO_VERSION_CHECK relaxes the host/guest driver version check.
      environment.__RM_NO_VERSION_CHECK = "1";
      serviceConfig = {
        Type = type;
        ExecStart = "${vgpuPackage.bin}/bin/${exec}";
        ExecStopPost = "${pkgs.coreutils}/bin/rm -rf /var/run/${exec}";
      }
      // extraServiceConfig;
    };
in
{
  options.hardware.nvidia.vgpu = {
    enable = lib.mkEnableOption "NVIDIA vGPU host (native SR-IOV, no unlock)";

    version = lib.mkOption {
      type = lib.types.str;
      description = "Host driver version — the number in the -vgpu-kvm.run filename.";
      example = "550.144.02";
    };

    driverUrl = lib.mkOption {
      type = lib.types.str;
      description = "URL of the NVIDIA `-vgpu-kvm.run` host installer (license-gated; host it yourself).";
    };

    driverSha256 = lib.mkOption {
      type = lib.types.str;
      description = "Hash of driverUrl. Get it with: nix store prefetch-file --name nvidia-vgpu-kvm.run <driverUrl>";
    };

    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = vgpuPackage;
      description = "The built vGPU host driver package (read-only, for reference).";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.driverUrl != "" && cfg.driverSha256 != "" && cfg.version != "";
        message = "hardware.nvidia.vgpu requires version, driverUrl and driverSha256 to be set.";
      }
    ];

    # Kernel modules + IOMMU for the mediated devices (mdev) the guests attach
    # to. Pascal/Turing/Volta create mdevs directly on the physical GPU (legacy
    # vGPU); SR-IOV vGPU is Ampere+ only, so there is no VF/sriov-manage step here.
    boot.extraModulePackages = [ vgpuPackage.mod ];
    boot.kernelModules = [
      "nvidia"
      "nvidia-vgpu-vfio"
    ];
    boot.kernelParams = [ "iommu=pt" ];

    # nouveau grabs the GPU at boot and blocks the proprietary module from
    # loading. The desktop hardware.nvidia module blacklists these for us; since
    # we bypass it, do it here.
    boot.blacklistedKernelModules = [
      "nouveau"
      "nvidiafb"
    ];

    # GSP firmware (shipped in the .run; harmless on GPUs that don't use it).
    hardware.firmware = [ vgpuPackage.firmware ];

    # Create the control + per-GPU device nodes once the nvidia module loads.
    # Same approach as the NixOS nvidia module, minus the modeset/uvm nodes the
    # host driver doesn't provide.
    services.udev.extraRules = ''
      KERNEL=="nvidia", RUN+="${pkgs.runtimeShell} -c 'mknod -m 666 /dev/nvidiactl c 195 255'"
      KERNEL=="nvidia", RUN+="${pkgs.runtimeShell} -c 'for i in $$(cat /proc/driver/nvidia/gpus/*/information | grep Minor | cut -d \  -f 4); do mknod -m 666 /dev/nvidia$${i} c 195 $${i}; done'"
    '';

    # Types match NVIDIA's official unit files shipped in the .run:
    # vgpud registers the vGPU types and exits (oneshot); vgpu-mgr is a
    # persistent forking daemon that services the running VMs.
    #
    # CRITICAL ordering: vgpu-mgr is what makes nvidia-vgpu-vfio register the
    # mdev parent (creating .../mdev_supported_types). It reads the vGPU types
    # from the driver at startup — if it runs before vgpud has finished
    # registering them, vfio logs "No vGPU types present" and never retries, so
    # mdev_supported_types is never created. vgpud being `oneshot` + mgr
    # `After`/`Requires` it guarantees mgr starts only once registration is done.
    systemd.services.nvidia-vgpud = mkVgpuDaemon {
      description = "NVIDIA vGPU Daemon";
      exec = "nvidia-vgpud";
      type = "oneshot";
    };
    systemd.services.nvidia-vgpu-mgr = mkVgpuDaemon {
      description = "NVIDIA vGPU Manager Daemon";
      exec = "nvidia-vgpu-mgr";
      type = "forking";
      after = [ "nvidia-vgpud.service" ];
      requires = [ "nvidia-vgpud.service" ];
      extraServiceConfig.KillMode = "process";
    };

    # Path must match the binary patch in postPatch above.
    environment.etc."nvidia-vgpu-xxxxx/vgpuConfig.xml".source = "${vgpuPackage}/vgpuConfig.xml";

    # nvidia-smi for the admin + mdevctl to manage/persist the mediated devices.
    environment.systemPackages = [
      vgpuPackage.bin
      pkgs.mdevctl
    ];
    services.udev.packages = [ pkgs.mdevctl ];
    # mdevctl expects these dirs to exist (persisted defs + callout/notifier
    # scripts); the Nix package can't create /etc dirs, so do it here. Without
    # them even `mdevctl types` errors out.
    systemd.tmpfiles.rules = [
      "d /etc/mdevctl.d 0755 root root - -"
      "d /etc/mdevctl/scripts.d 0755 root root - -"
      "d /etc/mdevctl/scripts.d/callouts 0755 root root - -"
      "d /etc/mdevctl/scripts.d/notifiers 0755 root root - -"
    ];
  };
}
