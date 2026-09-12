{
  ...
}:
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
      "2c" = "cd /Volumes/Code/";
    };

    initExtra = ''
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
    '';
  };

  # carapace completions register into bash-completion
  programs.carapace.enableBashIntegration = true;
}
