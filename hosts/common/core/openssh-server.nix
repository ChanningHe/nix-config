# OpenSSH Server Configuration (NixOS only)
#
# This module is imported only on Linux via default.nix.
# Darwin handles SSH differently via launchd.

{
  config,
  ...
}:
let
  # FIXME(starter): if you are not defining ports in your "soft" nix-secrets, you can
  # replace the following line with: sshPort = 22;
  # and substitute 22 with a custom port number if needed.
  sshPort = config.hostSpec.networking.ports.tcp.ssh;
in
{
  services.openssh = {
    enable = true;
    ports = [ sshPort ];

    settings = {
      # Harden
      PasswordAuthentication = false;
      # PAM keyboard-interactive would still accept the account password
      KbdInteractiveAuthentication = false;
      # Keys only; root's keys are hardware-backed (users/channinghe/nixos.nix)
      PermitRootLogin = "prohibit-password";
      # Automatically remove stale sockets
      StreamLocalBindUnlink = "yes";
      # Allow forwarding ports to everywhere
      GatewayPorts = "clientspecified";
    };

    # Root reads only the Nix-managed (sk-only) key file, never a mutable
    # /root/.ssh/authorized_keys. Other users (e.g. rl-man) keep the homedir file.
    extraConfig = ''
      Match User root
        AuthorizedKeysFile /etc/ssh/authorized_keys.d/%u
    '';

    hostKeys = [
      {
        path = "/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };

  networking.firewall.allowedTCPPorts = [ sshPort ];
}
