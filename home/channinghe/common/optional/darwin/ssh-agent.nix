# SSH Agent configuration for Darwin - optimized for performance
# Single ssh-agent instance shared across all terminals with lazy key loading
{
  pkgs,
  lib,
  ...
}:
{
  # Ensure Nix-managed OpenSSH is available
  home.packages = with pkgs; [
    openssh
  ];

  # Environment variables for SSH
  home.sessionVariables = {
    SSH_ASKPASS = "/opt/homebrew/bin/ssh-askpass";
    DISPLAY = ":0";
  };

  # SSH agent configuration with single-instance guarantee
  programs.zsh.initContent = lib.mkAfter ''
    # ===== SSH Agent Management - Performance Optimized =====

    # Force use of Nix-managed SSH tools (not macOS system versions)
    NIX_SSH_ADD="/run/current-system/sw/bin/ssh-add"
    NIX_SSH_AGENT="/run/current-system/sw/bin/ssh-agent"

    # Use fixed socket path for stability (survives restarts, accessible by root)
    SSH_AUTH_SOCK="$HOME/.ssh/ssh-agent.sock"
    export SSH_AUTH_SOCK

    # Start or connect to existing agent (fast path)
    _ssh_agent_start() {
      # Check if socket exists and agent is responsive
      if [ -S "$SSH_AUTH_SOCK" ]; then
        # Quick check: can we list keys? (agent is alive)
        if $NIX_SSH_ADD -l >/dev/null 2>&1; then
          return 0
        fi
      fi

      # Clean up stale socket
      [ -e "$SSH_AUTH_SOCK" ] && rm -f "$SSH_AUTH_SOCK"

      # Start new agent with fixed socket path
      $NIX_SSH_AGENT -a "$SSH_AUTH_SOCK" -s >/dev/null
      chmod 600 "$SSH_AUTH_SOCK"
    }

    # Load SSH keys lazily (only when first needed)
    ssh() {
      # Fast path: if keys already loaded, just run ssh
      if $NIX_SSH_ADD -l >/dev/null 2>&1; then
        command ssh "$@"
        return
      fi

      # Keys not loaded yet, load them now
      local keys=(
        "$HOME/.ssh/yk-976-main"
        "$HOME/.ssh/id-yk5c-806"
      )

      for key in "''${keys[@]}"; do
        [ -f "$key" ] && $NIX_SSH_ADD "$key" 2>/dev/null
      done

      command ssh "$@"
    }

    # Initialize agent connection (non-blocking)
    _ssh_agent_start

    # Aliases (using Nix ssh-add)
    alias ssh-list="$NIX_SSH_ADD -l"
    alias ssh-clear="$NIX_SSH_ADD -D"
  '';
}
