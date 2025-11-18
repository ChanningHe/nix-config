# SSH Agent auto-loading configuration for Darwin
# This module provides intelligent SSH key management with auto-loading capabilities
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

  # Environment variables for SSH (Darwin-specific with ssh-askpass)
  home.sessionVariables = {
    # Use homebrew's ssh-askpass for GUI password prompts on Darwin
    SSH_ASKPASS = "/opt/homebrew/bin/ssh-askpass";
    DISPLAY = ":0";
  };

  # Intelligent SSH key auto-loading
  programs.zsh.initExtra = lib.mkAfter ''
    # ===== SSH Agent Management =====
    
    # Ensure we use Nix-provided ssh-add (not system version)
    NIX_SSH_ADD="/run/current-system/sw/bin/ssh-add"
    NIX_SSH_AGENT="/run/current-system/sw/bin/ssh-agent"
    
    # Function to check if ssh-agent is running
    ssh_agent_check() {
      if [ -z "$SSH_AUTH_SOCK" ]; then
        echo "⚠️  SSH agent not running"
        return 1
      fi
      
      # Test if agent is actually responsive
      if ! $NIX_SSH_ADD -l &>/dev/null; then
        echo "⚠️  SSH agent not responsive"
        return 1
      fi
      
      return 0
    }
    
    # Function to check if specific key is loaded
    ssh_key_loaded() {
      local key_path="$1"
      local key_fingerprint
      
      # Get public key fingerprint
      if [ -f "$key_path" ]; then
        key_fingerprint=$(ssh-keygen -lf "$key_path" 2>/dev/null | awk '{print $2}')
        
        # Check if this fingerprint is in loaded keys
        if $NIX_SSH_ADD -l 2>/dev/null | grep -q "$key_fingerprint"; then
          return 0
        fi
      fi
      
      return 1
    }
    
    # Auto-load SSH keys on shell startup
    ssh_autoload_keys() {
      # Define your SSH keys to auto-load
      local keys=(
        "$HOME/.ssh/id_976_main"
        # Add more keys here if needed
      )
      
      # Check agent first
      if ! ssh_agent_check; then
        echo "🔐 Starting SSH agent (Nix-managed)..."
        eval "$($NIX_SSH_AGENT -s)" &>/dev/null
      fi
      
      # Load each key if not already loaded
      for key in "''${keys[@]}"; do
        if [ -f "$key" ]; then
          if ! ssh_key_loaded "$key"; then
            echo "🔑 Loading SSH key: $(basename $key)"
            $NIX_SSH_ADD "$key" 2>/dev/null
          fi
        fi
      done
      
      # Show loaded keys status
      local loaded_count=$($NIX_SSH_ADD -l 2>/dev/null | wc -l | tr -d ' ')
      if [ "$loaded_count" -gt 0 ]; then
        echo "✅ SSH agent ready ($loaded_count key(s) loaded)"
      fi
    }
    
    # Run auto-load on shell startup (only once per session)
    if [ -z "$SSH_KEYS_LOADED" ]; then
      ssh_autoload_keys
      export SSH_KEYS_LOADED=1
    fi
    
    # Convenient aliases using Nix ssh-add/agent
    alias ssh-add-nix="$NIX_SSH_ADD"
    alias ssh-agent-nix="$NIX_SSH_AGENT"
    alias ssh-list="$NIX_SSH_ADD -l"
    alias ssh-clear="$NIX_SSH_ADD -D"
  '';
}

