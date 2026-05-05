# Clean Zsh configuration with Antidote + Powerlevel10k
{
  lib,
  pkgs,
  ...
}:
{
  dotfiles = {
    enable = true;
    installAll = true;
    # components = [
    #   "p10k"
    #   "ghostty"
    # ];
  };

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
      ls = "ls --color=auto";
      ".." = "cd ..";
      "..." = "cd ../..";
      "2dot" = "cd $HOME/.config/dotfiles";
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
          export CLICOLOR=1
          export LS_COLORS=$(vivid generate nord)
          # Remove / and . from WORDCHARS to make path navigation easier (Ctrl+W stops at /)
          # Note: We use ''${...} to escape the Nix interpolation and pass it literally to Zsh
          WORDCHARS="''${WORDCHARS//\//}"
          WORDCHARS="''${WORDCHARS//./}"
          # ==== ZSH Command Line  ====
          # Edit Command Line
          autoload -Uz edit-command-line
          zle -N edit-command-line
          bindkey '^xe' edit-command-line

          # Magic Space
          bindkey ' ' magic-space
          # Undo
          bindkey '^_' undo
          # Redo
          bindkey '^x^_' redo

          # ==== ZSH Syntax Highlighting Styles ====
          # Commands (retro green)
          ZSH_HIGHLIGHT_STYLES[command]='fg=112'        # External commands
          ZSH_HIGHLIGHT_STYLES[builtin]='fg=112'        # Builtin commands
          ZSH_HIGHLIGHT_STYLES[function]='fg=112'       # Functions
          ZSH_HIGHLIGHT_STYLES[alias]='fg=112'          # Aliases
          ZSH_HIGHLIGHT_STYLES[precommand]='fg=114'     # Precommands (sudo, time, etc.)

          # Subcommands and first argument (lighter green for distinction)
          ZSH_HIGHLIGHT_STYLES[arg0]='fg=f8f8f2'           # Subcommands like 'push', 'develop'
          ZSH_HIGHLIGHT_STYLES[default]='fg=f8f8f2'

          # Arguments and parameters (muted color)
          ZSH_HIGHLIGHT_STYLES[argument]='fg=109'
          ZSH_HIGHLIGHT_STYLES[parameter]='fg=109'
          ZSH_HIGHLIGHT_STYLES[parameter-expansion]='fg=109'

          # Options (same as arguments)
          ZSH_HIGHLIGHT_STYLES[single-hyphen-option]='fg=109'
          ZSH_HIGHLIGHT_STYLES[double-hyphen-option]='fg=109'
          ZSH_HIGHLIGHT_STYLES[option]='fg=109'

          # Paths (subtle blue-gray)
          ZSH_HIGHLIGHT_STYLES[path]='fg=145'
          ZSH_HIGHLIGHT_STYLES[path_prefix]='fg=145,underline'

          # Errors
          ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=124,bold'

          # Highlight current selection with distinct background color
          zle_highlight=(suffix:fg=092,bold)
          # ==== marlonrichert/zsh-autocomplete configuration ====
          # Fix issue with marlonrichert/zsh-autocomplete
          #bindkey "''${key[Up]}" up-line-or-search
          zstyle -e ':autocomplete:*:*' list-lines 'reply=( $(( LINES / 3 )) )'
          zstyle ':completion:*' completer _expand _complete _complete:-loose _complete:-fuzzy _ignored

          # Override for history search only
          zstyle ':autocomplete:history-incremental-search-backward:*' list-lines 8

          # autocomplete delay and input
          zstyle ':autocomplete:*' min-delay 0.5
          zstyle ':autocomplete:*' min-input 3
          zstyle ':autocomplete:*' timeout 1.5

          # Cycle through listed completions, without changing what's listed in the menu
          #bindkey              '^I'         menu-complete
          #bindkey "$terminfo[kcbt]" reverse-menu-complete
          # Enter the menu instead of inserting a completion
          # bindkey              '^I' menu-select
          # bindkey "$terminfo[kcbt]" reverse-menu-select

          # completion widget first insert the longest sequence of characters
          zstyle ':autocomplete:*complete*:*' insert-unambiguous yes

          # Tab: menu-select mode (arrow key navigation)
          #bindkey '^I' menu-complete
          bindkey '^I' menu-select

          # Shift+Tab: menu-complete (cycle through completions, works with insert-unambiguous)
          #bindkey "$terminfo[kcbt]" menu-select
          bindkey "$terminfo[kcbt]" menu-complete

          # In menuselect mode, Tab/Shift+Tab move selection
          bindkey -M menuselect '^I' menu-complete
          bindkey -M menuselect "$terminfo[kcbt]" reverse-menu-complete

          # Right arrow: accept current selection and continue to next level completion
          #bindkey -M menuselect '^[[C' accept-and-menu-complete
          #bindkey -M menuselect '^[OC' accept-and-menu-complete

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

          # Generate Conventional Commits message from staged changes
          gencommit() {
            local prompt="Run git diff --staged to inspect the staged changes, then"
            prompt+=" generate a one-line commit message in Conventional Commits format."
            prompt+=" Output only the message itself—no explanation, no markdown, no quotes."
            prompt+=" Type: feat/fix/refactor/chore/docs/style/test/build/ci/perf."
            prompt+=" Include a scope. Lowercase English, no trailing period, max 72 chars."
            claude -p "$prompt" --max-turns 3
          }
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
        # Important: in nix-config/hosts/common/users/channinghe/default.nix: disable completion and global comp init
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
