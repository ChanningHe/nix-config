# SSH config for the nix-daemon (root) to reach remote builders.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  primaryUser = config.hostSpec.username;
  primaryUserHome = "/Users/${primaryUser}";

  # Non-SK key pinned with IdentitiesOnly so builds never trigger a YubiKey touch.
  builderKey = "${primaryUserHome}/.ssh/hl-intrl";

  sshClientsInfo = inputs.nix-secrets.sshClientsInfo or { };

  # Render one root-scoped block per host so root can resolve builder aliases.
  # `localuser` (not `user`) matches the local nix-daemon, not the remote login.
  formatRootHostBlock =
    name: configStr:
    let
      lines = lib.filter (l: l != "") (lib.splitString "\n" (lib.trim configStr));
      indented = lib.concatStringsSep "\n" (map (l: "  ${lib.trim l}") lines);
    in
    "Match localuser root host ${name}\n${indented}";

  rootHostBlocks = lib.concatStringsSep "\n\n" (
    lib.mapAttrsToList formatRootHostBlock sshClientsInfo
  );
in
{
  environment.etc."ssh/ssh_config.d/999-root-builder.conf".text = ''
    Match localuser root
      IdentityAgent ${primaryUserHome}/.ssh/ssh-agent.sock
      UserKnownHostsFile ${primaryUserHome}/.ssh/known_hosts
      GlobalKnownHostsFile /etc/ssh/ssh_known_hosts
      StrictHostKeyChecking accept-new
      ControlMaster auto
      ControlPath ${primaryUserHome}/.ssh/sockets/S.%r@%h:%p
      ControlPersist 20m
      ServerAliveInterval 60
      ServerAliveCountMax 3
      #IdentityFile ${builderKey}
      IdentitiesOnly yes

    ${rootHostBlocks}
  '';

  # `test-root-ssh`: diagnose root's agent/known_hosts access.
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

      echo "Agent socket exists"

      # Test agent access as root
      if sudo SSH_AUTH_SOCK="${primaryUserHome}/.ssh/ssh-agent.sock" ${pkgs.openssh}/bin/ssh-add -l >/dev/null 2>&1; then
        echo "Root can access agent"
        sudo SSH_AUTH_SOCK="${primaryUserHome}/.ssh/ssh-agent.sock" ${pkgs.openssh}/bin/ssh-add -l
      else
        echo "❌ Root cannot access agent (permission issue?)"
        ls -la "${primaryUserHome}/.ssh/ssh-agent.sock"
        exit 1
      fi

      echo ""
      echo "Known hosts: ${primaryUserHome}/.ssh/known_hosts"
      if [ -f "${primaryUserHome}/.ssh/known_hosts" ]; then
        echo "Known hosts exists"
        ls -la "${primaryUserHome}/.ssh/known_hosts"
      else
        echo "!! Known hosts not found"
      fi
    '')
  ];
}
