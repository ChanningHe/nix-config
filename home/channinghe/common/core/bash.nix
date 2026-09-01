# Bash + flyline
{
  lib,
  pkgs,
  inputs,
  ...
}:
let
  flyline = inputs.flyline.packages.${pkgs.stdenv.hostPlatform.system}.default;
  flylineLib = "libflyline.${if pkgs.stdenv.hostPlatform.isDarwin then "dylib" else "so"}";

  # Async git segment for the prompt (flyline custom widget; output goes
  # through bash's decode_prompt_string, so \e color escapes work).
  # Shows " branch +staged !unstaged ?untracked", nothing outside a repo.
  flylineGitPrompt = pkgs.writeShellScript "flyline-git-prompt" ''
    branch=$(git symbolic-ref --short HEAD 2>/dev/null) \
      || branch=$(git rev-parse --short HEAD 2>/dev/null) \
      || exit 0
    staged=0 unstaged=0 untracked=0
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      case "$line" in
        '??'*) untracked=$((untracked + 1)) ;;
        *)
          [ "''${line:0:1}" != " " ] && staged=$((staged + 1))
          [ "''${line:1:1}" != " " ] && unstaged=$((unstaged + 1))
          ;;
      esac
    done <<<"$(git status --porcelain --no-renames 2>/dev/null)"
    out=" \e[1;32m''${branch}\e[0m"
    [ "$staged" -gt 0 ] && out="$out \e[32m+''${staged}\e[0m"
    [ "$unstaged" -gt 0 ] && out="$out \e[33m!''${unstaged}\e[0m"
    [ "$untracked" -gt 0 ] && out="$out \e[36m?''${untracked}\e[0m"
    printf '%s' "$out"
  '';
in
{
  programs.bash = {
    enable = true;
    enableCompletion = true;

    # Mirror zsh history settings (zsh.nix)
    historySize = 10000;
    historyFileSize = 10000;
    historyControl = [
      "ignoredups"
      "ignorespace"
    ];

    # Mirror zsh.nix aliases; consolidation into home.shellAliases is a
    # phase-6 cleanup once the bash stack is validated
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

    initExtra = lib.mkMerge [
      ''
        [[ ! $(command -v nix) && -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]] && source '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'

        export CLICOLOR=1

        # Generate Conventional Commits message from staged changes
        gcm() {
          local prompt="Run git diff --staged to inspect the staged changes, then"
          prompt+=" generate a one-line commit message in Conventional Commits format."
          prompt+=" Output only the message itself—no explanation, no markdown, no quotes."
          prompt+=" Type: feat/fix/refactor/chore/docs/style/test/build/ci/perf."
          prompt+=" Include a scope. Lowercase English, no trailing period, max 50 chars."
          claude -p "$prompt" --max-turns 3
        }
      ''

      (lib.mkOrder 2000 ''
        enable -f ${flyline}/lib/${flylineLib} flyline

        flyline --set-frame-rate 60
        # p10k-like prompt: cwd + async git widget · duration + clock / ❯ input
        flyline create-prompt-widget custom --name FLYLINE_GIT_INFO \
          --command '${flylineGitPrompt}' --placeholder prev
        flyline create-prompt-widget last-command-duration

        PROMPT_DIRTRIM=5

        # Rebuild PS1 each prompt: ❯ turns red after a failing command
        source ${pkgs.bash-preexec}/share/bash/bash-preexec.sh
        __flyline_set_ps1() {
          local last_status=$?
          local char_color='\[\e[1;32m\]'
          [ "$last_status" -ne 0 ] && char_color='\[\e[1;31m\]'
          # Show user@host when this shell was reached over SSH
          local ssh_part=""
          [ -n "''${SSH_TTY:-}''${SSH_CONNECTION:-}" ] && ssh_part='\[\e[1;35m\]\u@\h\[\e[0m\] '
          PS1="$ssh_part"'\[\e[1;34m\]\w\[\e[0m\]FLYLINE_GIT_INFO\n'"$char_color"'❯\[\e[0m\] '
        }
        precmd_functions+=(__flyline_set_ps1)

        RPS1='\e[2mFLYLINE_LAST_COMMAND_DURATION \t\e[0m'
        PS1_FILL='\e[2m·\e[0m'
        PS2='\e[2mFLYLINE_PROMPT_LINE_NUMBER❯\e[0m '

        flyline set-cursor --effect blink

        # Right arrow accepts the highlighted tab-completion entry (like Enter)
        flyline key bind Right tabCompletionEntrySelected=tabCompletionAcceptEntry
        flyline suggestions --auto-suggest
      '')
    ];
  };

  # flyline covers history search and suggestions
  programs.atuin.enableBashIntegration = false;
  programs.zoxide.enableBashIntegration = false;

  # carapace completions register into bash-completion
  programs.carapace.enableBashIntegration = true;
}
