# Service users for nixos-rl
#
# Purpose: Isolate file permissions across different services.
# These are system users with no login shell by default.
#
# Usage: Add `./service-users.nix` to the imports list in default.nix
#        when you need these users activated on this host.
#
# UID/GID allocation on this host:
#   3000  channinghe  (primary user)
#   5000  rl-man      (application runner)
#   6001+ service-*   (service isolation users, defined below)
#
{ ... }:
{
  # ---------------------------------------------------------------------------
  # Groups
  # ---------------------------------------------------------------------------
  users.groups = {
    svc-example = {
      gid = 6001;
    };
    # svc-another = { gid = 6002; };
  };

  # ---------------------------------------------------------------------------
  # Users
  # ---------------------------------------------------------------------------
  users.users = {
    # Template: duplicate and rename for each service that needs its own identity.
    svc-example = {
      uid = 6001;
      group = "svc-example";
      isSystemUser = true; # No login, UID < 1000 unless explicitly set above

      # Shell is nologin for system users by default.
      # Uncomment the line below if interactive access is ever needed:
      # shell = pkgs.bash;

      home = "/var/lib/svc-example";
      createHome = false; # Managed by systemd.tmpfiles below

      description = "Service isolation user: example";

      # Add to shared groups only when strictly required by the service.
      # Common candidates: "docker", "rl"
      extraGroups = [ ];
    };

    # svc-another = {
    #   uid = 6002;
    #   group = "svc-another";
    #   isSystemUser = true;
    #   home = "/var/lib/svc-another";
    #   createHome = false;
    #   description = "Service isolation user: another";
    #   extraGroups = [ ];
    # };
  };

  # ---------------------------------------------------------------------------
  # Home directories (systemd tmpfiles)
  # Use /var/lib/<name> for service state data (FHS convention).
  # Adjust mode as needed; 0750 prevents other users from listing contents.
  # ---------------------------------------------------------------------------
  systemd.tmpfiles.rules = [
    "d /var/lib/svc-example 0750 svc-example svc-example -"
    # "d /var/lib/svc-another 0750 svc-another svc-another -"
  ];
}
