# Zsh configuration: native compsys + carapace + autosuggestions + atuin + zoxide + zsh-patina
#
# Stack overview (replaces marlonrichert/zsh-autocomplete, which ran the full
# compsys pipeline on every keystroke and caused lag/freezes):
#   - Tab completion ....... native compsys menu (menu select) + carapace
#   - As-you-type hints .... zsh-autosuggestions (inline ghost text from history)
#   - History search ....... atuin (Ctrl+R TUI)
#   - Directory jumping .... zoxide (frecency-ranked `cd`)
#   - Syntax highlighting .. zsh-patina (Rust daemon, via flake input)
#   (fzf-tab / fzf shell integration currently disabled; kept as comments below)
#
# home-manager .zshrc ordering (lib.mkOrder):
#   550 antidote (p10k) -> 570 compinit -> 650 carapace + completion zstyles (ours)
#   -> 700 autosuggestions -> 851 zoxide -> 1000 initContent/atuin
#   -> 1200 atuin autosuggest strategy override (ours)
#   -> 1400 patina (ours) -> mkAfter p10k config
{
  lib,
  pkgs,
  inputs,
  ...
}:
let
  zsh-patina = inputs.zsh-patina.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  dotfiles = {
    enable = true;
    installAll = true;
    # components = [
    #   "p10k"
    #   "ghostty"
    # ];
  };

  home.packages = [
    zsh-patina
    # fzf binary WITHOUT shell integration: zoxide's interactive mode
    pkgs.fzf
  ];

  programs.zsh = {
    enable = true;

    # Run compinit once here (order 570); system-level enableGlobalCompInit stays false
    enableCompletion = true;

    # Fish-like inline suggestions from history, accept with Right arrow (order 700)
    autosuggestion.enable = true;

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
      "2dd" = "cd $DOCKER_DATA";
      "2dot" = "cd $HOME/.config/dotfiles";

      "claude-auto" = "claude --permission-mode auto";
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

      # Completion setup: must load after compinit (570) and before autosuggestions (700)
      # NOTE: fzf-tab temporarily commented out to try native compsys menu + carapace
      (lib.mkOrder 650 ''
        # Colorized ls; LS_COLORS must be set before the list-colors zstyle below
        export CLICOLOR=1
        #export LS_COLORS=$(vivid generate nord)

        # Silence zoxide's "not the last precmd hook" warning. In our stack
        # atuin (order 1000) and p10k (mkAfter) legitimately register precmd
        # hooks after zoxide (order 851), and none of them mutate $PWD inside
        # precmd, so the warning is cosmetic.
        export _ZO_DOCTOR=0

        # source ${pkgs.zsh-fzf-tab}/share/fzf-tab/fzf-tab.plugin.zsh

        # ==== carapace: multi-shell completion engine ====
        source <(${pkgs.carapace}/bin/carapace _carapace zsh)

        # ==== Completion behavior ====
        zstyle ':completion:*' completer _expand _complete _ignored
        # Case-insensitive matching, plus partial-word on . _ - separators
        zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*'
        # Native menu selection: Tab opens the menu, arrows/Tab navigate
        zstyle ':completion:*' menu select
        zstyle ':completion:*:descriptions' format '[%d]'
        zstyle ':completion:*' list-colors ''${(s.:.)LS_COLORS}

        # ==== fzf-tab UI (disabled along with fzf-tab) ====
        # zstyle ':completion:*' menu no
        # zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls --color=always $realpath'
        # zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'ls --color=always $realpath'
        # zstyle ':fzf-tab:*' switch-group '<' '>'
      '')

      # Other initialization (normal priority, runs after plugins)
      (
        ''
          # Remove / and . from WORDCHARS to make path navigation easier (Ctrl+W stops at /)
          # Note: We use ''${...} to escape the Nix interpolation and pass it literally to Zsh
          WORDCHARS="''${WORDCHARS//\//}"
          WORDCHARS="''${WORDCHARS//./}"
          # ==== ZSH Command Line  ====
          # Edit Command Line
          autoload -Uz edit-command-line
          zle -N edit-command-line
          bindkey '^xe' edit-command-line

          # Option+Up/Down: prefix-filtered history search — type `git commit`,
          # press Option+Up to cycle only entries starting with "git commit".
          # Plain Up/Down keep the default history stepping.
          autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
          zle -N up-line-or-beginning-search
          zle -N down-line-or-beginning-search
          bindkey '^[[1;3A' up-line-or-beginning-search # kitty/ghostty/xterm style
          bindkey '^[[1;3B' down-line-or-beginning-search
          bindkey '^[^[[A' up-line-or-beginning-search # Terminal.app/iTerm ESC-prefix style
          bindkey '^[^[[B' down-line-or-beginning-search

          # Magic Space
          bindkey ' ' magic-space
          # Undo
          bindkey '^_' undo
          # Redo
          bindkey '^x^_' redo

          # Highlight current selection with distinct background color
          zle_highlight=(suffix:fg=092,bold)

          # Generate Conventional Commits message from staged changes
          gcm() {
            local prompt="Run git diff --staged to inspect the staged changes, then"
            prompt+=" generate a one-line commit message in Conventional Commits format."
            prompt+=" Output only the message itself—no explanation, no markdown, no quotes."
            prompt+=" Type: feat/fix/refactor/chore/docs/style/test/build/ci/perf/add/update."
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

      # Override atuin's built-in autosuggest strategy with directory-aware filtering.
      # Must run AFTER `atuin init zsh` (order 1000) so we override its function.
      # The upstream strategy uses no filter, so its suggestions equal plain history;
      # this version prioritizes commands previously run in the current directory and
      # falls back to global history when there's no per-directory match.
      # Workaround for atuin#1769 (filter_mode in config.toml is not honored by the
      # built-in autosuggest strategy).
      (lib.mkOrder 1200 ''
        _zsh_autosuggest_strategy_atuin() {
          suggestion=$(
            ATUIN_QUERY="$1" atuin search \
              --cmd-only --limit 1 \
              --search-mode prefix \
              --filter-mode directory \
              2>/dev/null
          )
          if [[ -z "$suggestion" ]]; then
            suggestion=$(ATUIN_QUERY="$1" atuin search --cmd-only --limit 1 --search-mode prefix 2>/dev/null)
          fi
        }
      '')

      # zsh-patina: upstream requires activation at the very end of .zshrc,
      # after all widgets/bindkeys are set up (only p10k config sourcing follows)
      (lib.mkOrder 1400 ''
        eval "$(zsh-patina activate)"
      '')

      # Load P10k config AFTER plugins are loaded
      (lib.mkAfter ''
        # Load Powerlevel10k config (managed by home-manager from repo)
        [[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh
      '')
    ];

    # Antidote plugin manager: only the prompt theme remains; everything else
    # is handled by home-manager modules / nixpkgs packages above
    antidote = {
      enable = true;
      plugins = [
        # Powerlevel10k theme (fast and beautiful)
        "romkatv/powerlevel10k"
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

  # fzf shell integration (Ctrl+T / Alt+C / ** completion);
  # keep the bare binary on PATH because `zi` (interactive zoxide) needs it
  # programs.fzf.enable = true;

  # Smart cd: frecency-ranked jumping, `cd foo` matches deep dirs, `cdi` interactive
  programs.zoxide = {
    enable = true;
    options = [
      "--cmd"
      "cd"
    ];
  };

  # carapace package; zsh integration is sourced manually in the completion
  # block above (right after compinit, per upstream docs) instead of here
  programs.carapace = {
    enable = true;
    enableZshIntegration = false;
  };

  # History: Ctrl+R opens atuin TUI (loads after fzf, so it owns Ctrl+R).
  # Up arrow stays native zsh history. Fully local, no sync.
  programs.atuin = {
    enable = true;
    flags = [ "--disable-up-arrow" ];
    settings = {
      auto_sync = false;
      update_check = false;
      search_mode = "fuzzy";
    };
  };
}
