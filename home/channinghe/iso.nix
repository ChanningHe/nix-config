# Home configuration for channinghe user on ISO
# This is a minimal configuration for the ISO environment
{ ... }:
{
  imports = [
    #
    # ========== Required Configs ==========
    #
    common/core

    #
    # ========== ISO-specific Optional Configs ==========
    #
    # Keep it minimal for ISO
  ];
}