# Clean Zsh configuration with Antidote + Powerlevel10k
{
  lib,
  pkgs,
  ...
}:
let
  # Path to p10k config from dotfiles directory
  p10kConfig = ../dotfiles/p10k.zsh;
in
{
  # Link p10k config from repo to home directory
  home.file.".p10k.zsh".source = p10kConfig;

  programs.zsh = {
    enable = true;

    # "marlonrichert/zsh-autocomplete" requires this to be disabled
    enableCompletion = false;

    # Shell aliases
    shellAliases = {
      # Nix shortcuts
      nxsw = "sudo nixos-rebuild switch";
      nx = "sudo nixos-rebuild";

      # Common shortcuts
      ll = "ls -lah";
      ".." = "cd ..";
      "..." = "cd ../..";
    };

    # Initialization content with proper priority ordering
    # Using lib.mkMerge to combine multiple initContent blocks with different priorities
    initContent = lib.mkMerge [
      # P10k instant prompt - must be loaded BEFORE everything (highest priority)
      (lib.mkBefore ''
        # Enable Powerlevel10k instant prompt (must be at the very top)
        if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
          source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
        fi
      '')

      # Load P10k config AFTER plugins are loaded
      (lib.mkAfter ''
        # Load Powerlevel10k config (managed by home-manager from repo)
        [[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh
      '')

      # Other initialization (normal priority, runs after plugins)
      (
        ''
          # Colorized ls commands
          # export CLICOLOR=1
          # export LS_COLORS='di=34:ln=35:so=32:pi=33:ex=31:bd=34;46:cd=34;43:su=30;41:sg=30;46:tw=30;42:ow=30;43'
          # Remove / and . from WORDCHARS to make path navigation easier (Ctrl+W stops at /)
          # Note: We use ''${...} to escape the Nix interpolation and pass it literally to Zsh
          WORDCHARS="''${WORDCHARS//\//}"
          WORDCHARS="''${WORDCHARS//./}"

          # ==== marlonrichert/zsh-autocomplete configuration ====
          # Fix issue with marlonrichert/zsh-autocomplete
          #bindkey "''${key[Up]}" up-line-or-search
          zstyle -e ':autocomplete:*:*' list-lines 'reply=( $(( LINES / 3 )) )'
          # Override for history search only
          zstyle ':autocomplete:history-incremental-search-backward:*' list-lines 8
          zstyle ':autocomplete:*' min-delay 0.1
          zstyle ':autocomplete:*' min-input 2
          # systemctl completion without directories/files
          zstyle ':completion:*:systemctl-*:*' file-patterns
          zstyle ':completion:*:systemctl-*:*' tag-order '! directories ! files' -
          # ==== marlonrichert/zsh-autocomplete configuration ====
          # Cycle through listed completions, without changing what's listed in the menu
          #bindkey              '^I'         menu-complete
          #bindkey "$terminfo[kcbt]" reverse-menu-complete
          # Enter the menu instead of inserting a completion
          bindkey              '^I' menu-select
          bindkey "$terminfo[kcbt]" reverse-menu-select
          # Restore Zsh-default history shortcuts
          bindkey -M emacs \
            "^[p"   .history-search-backward \
            "^[n"   .history-search-forward \
            "^P"    .up-line-or-history \
            "^[OA"  .up-line-or-history \
            "^[[A"  .up-line-or-history \
            "^N"    .down-line-or-history \
            "^[OB"  .down-line-or-history \
            "^[[B"  .down-line-or-history \
            "^R"    .history-incremental-search-backward \
            "^S"    .history-incremental-search-forward

          bindkey -a \
            "^P"    .up-history \
            "^N"    .down-history \
            "k"     .up-line-or-history \
            "^[OA"  .up-line-or-history \
            "^[[A"  .up-line-or-history \
            "j"     .down-line-or-history \
            "^[OB"  .down-line-or-history \
            "^[[B"  .down-line-or-history \
            "/"     .vi-history-search-backward \
            "?"     .vi-history-search-forward
          # ==== marlonrichert/zsh-autocomplete configuration ====
        ''
        + lib.optionalString pkgs.stdenv.isDarwin ''
          # Source Nix daemon if available (macOS only)
          [[ ! $(command -v nix) && -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]] && \
            source '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
        ''
      )
    ];

    # Antidote plugin manager (modern, fast, simple)
    antidote = {
      enable = true;
      plugins = [
        # Powerlevel10k theme (fast and beautiful)
        "romkatv/powerlevel10k"

        # Essential plugins
        #"zsh-users/zsh-autosuggestions" # Fish-like autosuggestions
        "zsh-users/zsh-syntax-highlighting" # Syntax highlighting
        #"zsh-users/zsh-completions" # Additional completions
        "marlonrichert/zsh-autocomplete"
      ];
    };

    # Zsh options for better behavior
    history = {
      size = 10000;
      save = 10000;
      path = "$HOME/.zsh_history";
      ignoreDups = true;
      ignoreSpace = true;
      share = true;
    };
  };
}
