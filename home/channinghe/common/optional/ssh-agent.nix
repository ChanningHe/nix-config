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

    SSH_ENV="$HOME/.ssh/agent-env"

    # Start or connect to existing agent (fast path)
    _ssh_agent_start() {
      # Check if env file exists and agent is still running
      if [ -f "$SSH_ENV" ]; then
        source "$SSH_ENV" >/dev/null
        # Quick check: is this agent alive?
        if kill -0 "$SSH_AGENT_PID" 2>/dev/null; then
          return 0
        fi
      fi

      # Start new agent only if needed (using Nix ssh-agent)
      $NIX_SSH_AGENT -s | grep -v '^echo' > "$SSH_ENV"
      chmod 600 "$SSH_ENV"
      source "$SSH_ENV" >/dev/null
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
        "$HOME/.ssh/id_976_main"
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
