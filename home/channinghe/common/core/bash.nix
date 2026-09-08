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
    # branch/clean 76, modified 178, untracked 39
    out=" \e[38;5;76m''${branch}\e[0m"
    [ "$staged" -gt 0 ] && out="$out \e[38;5;178m+''${staged}\e[0m"
    [ "$unstaged" -gt 0 ] && out="$out \e[38;5;178m!''${unstaged}\e[0m"
    [ "$untracked" -gt 0 ] && out="$out \e[38;5;39m?''${untracked}\e[0m"
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

    shellAliases = {
      # Common shortcuts
      ll = "ls -lah";
      ls = "ls --color=auto";
      ".." = "cd ..";
      "..." = "cd ../..";
      "2dd" = "cd $DOCKER_DATA";
      "2dot" = "cd $HOME/.config/dotfiles";
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
        # Load flyline only when the terminal is sane and the builtin actually
        # loads; otherwise fall back to plain readline bash with a basic prompt.
        # Escape hatch: FLYLINE_DISABLE=1 bash
        if [[ $TERM != dumb && -z ''${FLYLINE_DISABLE:-} ]] \
            && enable -f ${flyline}/lib/${flylineLib} flyline 2>/dev/null; then
          flyline --set-frame-rate 60
          #  cwd + async git widget · duration + clock / > input
          flyline create-prompt-widget custom --name FLYLINE_GIT_INFO \
            --command '${flylineGitPrompt}' --placeholder prev
          flyline create-prompt-widget last-command-duration

          PROMPT_DIRTRIM=5

          # dir 108, char ok 71 / err 124,
          # ssh context 180, duration 101, clock 66, fill 244
          source ${pkgs.bash-preexec}/share/bash/bash-preexec.sh
          __flyline_set_ps1() {
            local last_status=$?
            local char_color='\[\e[1;38;5;71m\]'
            [ "$last_status" -ne 0 ] && char_color='\[\e[1;38;5;124m\]'
            # Show user@host when this shell was reached over SSH
            local ssh_part=""
            [ -n "''${SSH_TTY:-}''${SSH_CONNECTION:-}" ] && ssh_part='\[\e[38;5;180m\]\u@\h\[\e[0m\] '
            PS1="$ssh_part"'\[\e[38;5;108m\]\w\[\e[0m\]FLYLINE_GIT_INFO\n'"$char_color"'>\[\e[0m\] '
          }
          precmd_functions+=(__flyline_set_ps1)

          RPS1='\e[38;5;101mFLYLINE_LAST_COMMAND_DURATION \e[38;5;66m\t\e[0m'
          PS1_FILL='\e[38;5;244m·\e[0m'
          PS2='\e[38;5;244mFLYLINE_PROMPT_LINE_NUMBER>\e[0m '

          flyline set-cursor --effect blink

          # Right arrow accepts the highlighted tab-completion entry (like Enter)
          flyline key bind Right tabCompletionEntrySelected=tabCompletionAcceptEntry
          flyline suggestions --auto-suggest
        else
          # Basic fallback: plain prompt (conservative 16-color ANSI only),
          # user@host prefix when over SSH
          PS1='\[\e[1;34m\]\w\[\e[0m\]\n\[\e[1;32m\]>\[\e[0m\] '
          if [ -n "''${SSH_TTY:-}''${SSH_CONNECTION:-}" ]; then
            PS1='\[\e[1;35m\]\u@\h\[\e[0m\] '"$PS1"
          fi
        fi
      '')
    ];
  };

  # flyline covers history search and suggestions
  programs.atuin.enableBashIntegration = false;
  programs.zoxide.enableBashIntegration = false;

  # carapace completions register into bash-completion
  programs.carapace.enableBashIntegration = true;
}
