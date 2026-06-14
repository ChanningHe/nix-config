# LTO-6 tape drive operation toolkit.
# Import on NixOS hosts with an LTO drive or autoloader attached.
{ pkgs, ... }:
{
  environment.systemPackages = builtins.attrValues {
    inherit (pkgs)
      mt-st # `mt` — tape motion: rewind/eject/status/fsf/bsf/weof/erase
      mtx # SCSI media changer control (autoloaders / tape libraries)
      lsscsi # locate tape device paths (/dev/nst*, /dev/sg*)
      sg3_utils # SCSI inquiry, log pages, persistent reservations
      mbuffer # streaming buffer between tar ↔ tape (prevents shoeshining)
      pv # throughput / progress meter for tape pipelines
      stenc # SCSI hardware AES-256 encryption setup (LTO4+)
      lzop # fast compressor commonly chained with tar onto tape
      hpe-ltfs # LTFS userspace driver (HPE / Quantum LTO drives)
      ;
  };
}
