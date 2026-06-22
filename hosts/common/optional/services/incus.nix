# Incus (LXC/VM manager).
#
# Importing this file enables Incus on the host. The full `preseed` block (the
# initial networks / storage_pools / profiles applied on first start) is taken
# verbatim from nix-secrets:
#   serviceInfo.<hostName>.incus.preseed
# so per-host network/storage layout lives with the other private host config.
{ config, ... }:
let
  hostname = config.hostSpec.hostName;
  primaryUser = config.hostSpec.username;
  incusCfg = config.hostSpec.serviceInfo.${hostname}.incus or { };
in
{
  virtualisation.incus = {
    enable = true;
    # Pass the whole preseed through. `{ }` means "no preseed" (configure later
    # with `incus admin init` / the `incus` CLI).
    preseed = incusCfg.preseed or { };
  };

  users.users.${primaryUser}.extraGroups = [ "incus-admin" ];

  # Incus needs nftables for its managed-bridge firewall rules (NAT, DHCP/DNS).
  networking.nftables.enable = true;
}
