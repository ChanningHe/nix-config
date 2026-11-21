# Overrides for hosts with ~2-3GB RAM. Only tunes options; what a small host
# runs is decided by what its host file imports (attic, home dev tools, ...).
# Deploy these hosts from a bigger machine (`just deploy`), not locally;
# isLowMem makes deploy-rs build on the control machine instead of the target.
{
  hostSpec.isLowMem = true;

  # Compressed swap in RAM; there is no disk swap anywhere in this repo
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  # zram is cheap to swap to: prefer it over evicting page cache, no readahead
  boot.kernel.sysctl = {
    "vm.swappiness" = 180;
    "vm.page-cluster" = 0;
  };

  nix.settings = {
    download-buffer-size = 67108864; # nix default (64MB), core raises it to 500MB
    max-jobs = 1;
  };

  documentation = {
    enable = false;
    nixos.enable = false;
    man.enable = false;
    info.enable = false;
    doc.enable = false;
  };
}
