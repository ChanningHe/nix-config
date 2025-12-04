{ pkgs, ... }:
{
  users.groups.rl = {
    gid = 5000;
    members = [
      "channinghe"
      "rl-man"
      "docker"
    ];
  };

  # Create the rl-man user for running applications
  users.users.rl-man = {
    uid = 5000;
    group = "rl";
    isNormalUser = true;
    shell = pkgs.bash;
    home = "/home/rl-man";
    createHome = true;
    description = "Rootless user for running applications";

    # Minimal system groups - only what's absolutely necessary
    extraGroups = [ ];

    # No password login - use sudo from channinghe if needed
    hashedPassword = "!";

    # Add any tools needed for running applications here
    # packages = with pkgs; [ ];
  };

  # Create minimal home directory structure
  systemd.tmpfiles.rules = [
    "d /home/rl-man 0750 rl-man rl -"
    "d /home/rl-man/.local 0750 rl-man rl -"
    "d /home/rl-man/.local/bin 0750 rl-man rl -"
  ];
}
