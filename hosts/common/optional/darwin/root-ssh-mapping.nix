# Root SSH configuration for nix-darwin remote builders
# Allows root to use primary user's SSH agent and known_hosts
{
  config,
  pkgs,
  ...
}:
let
  primaryUser = config.hostSpec.username;
  primaryUserHome = "/Users/${primaryUser}";
in
{
  # Root SSH configuration (in root's home directory, not global)
  # This ensures only root uses the primary user's agent, not all system users
  environment.etc."ssh/ssh_config.d/999-root-builder.conf".text = ''
    # Root-only SSH config for nix-darwin remote builders
    # Only applies when effective UID is 0 (root)
    Match user root
      IdentityAgent ${primaryUserHome}/.ssh/ssh-agent.sock
      UserKnownHostsFile ${primaryUserHome}/.ssh/known_hosts
      GlobalKnownHostsFile /etc/ssh/ssh_known_hosts
      StrictHostKeyChecking accept-new
      ServerAliveInterval 60
      ServerAliveCountMax 3
  '';

  # Add helpful debug command for troubleshooting
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "test-root-ssh" ''
      echo "Testing root SSH configuration for builders..."
      echo "Primary user: ${primaryUser}"
      echo "Agent socket: ${primaryUserHome}/.ssh/ssh-agent.sock"
      echo ""

      if [ ! -S "${primaryUserHome}/.ssh/ssh-agent.sock" ]; then
        echo "❌ Agent socket not found. Is ${primaryUser} logged in with ssh-agent running?"
        exit 1
      fi

      echo "✅ Agent socket exists"

      # Test agent access as root
      if sudo SSH_AUTH_SOCK="${primaryUserHome}/.ssh/ssh-agent.sock" ${pkgs.openssh}/bin/ssh-add -l >/dev/null 2>&1; then
        echo "✅ Root can access agent"
        sudo SSH_AUTH_SOCK="${primaryUserHome}/.ssh/ssh-agent.sock" ${pkgs.openssh}/bin/ssh-add -l
      else
        echo "❌ Root cannot access agent (permission issue?)"
        ls -la "${primaryUserHome}/.ssh/ssh-agent.sock"
        exit 1
      fi

      echo ""
      echo "Known hosts: ${primaryUserHome}/.ssh/known_hosts"
      if [ -f "${primaryUserHome}/.ssh/known_hosts" ]; then
        echo "✅ Known hosts exists"
        ls -la "${primaryUserHome}/.ssh/known_hosts"
      else
        echo "⚠️  Known hosts not found"
      fi
    '')
  ];
}
