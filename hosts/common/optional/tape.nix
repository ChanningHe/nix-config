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
      # hpe-ltfs # superseded by `ltfs` below — both ship ltfs/mkltfs/ltfsck, so they collide in systemPackages
      ltfs # open-source LTFS (IBM reference impl, sg backend): mkltfs/ltfs/ltfsck — mount LTO tapes as a filesystem
      ;
  };
}
