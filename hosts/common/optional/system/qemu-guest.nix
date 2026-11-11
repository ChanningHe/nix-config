{
  ...
}:
{
  services.qemuGuest.enable = true;

  # Virtual hardware needs no firmware blobs or CPU microcode (the hypervisor owns it)
  hardware.enableRedistributableFirmware = false;
}
