# Dotfiles Configuration Module
#
# The actual dotfile mappings are defined in dotfiles/dotfiles.toml
# This keeps the Nix module simple and the config in one place (SSoT)
#
# Sync policy (deliberately minimal):
#   - repo missing            -> clone
#   - new home-manager gen    -> one `git pull --ff-only`; failure only warns
#   - same generation (boot)  -> no network access at all
#   - never deletes or resets the checkout; fix a broken/diverged repo by hand
#
# Prints nothing during activation; the last run's full output (git,
# getdots.sh) is in ~/.local/state/dotfiles-sync.log
#
# Usage:
#   dotfiles.enable = true;
#   dotfiles.components = [ "nvim" "p10k" ];  # or omit for all
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles;

  gitBin =
    if config.programs.git.enable then
      "${config.programs.git.package}/bin/git"
    else
      "${pkgs.git}/bin/git";

  defaultDir = "${config.home.homeDirectory}/.config/dotfiles";
  defaultRepoUrl = "https://github.com/ChanningHe/dotfiles.git";

  installArgs =
    if cfg.installAll then
      ""
    else if cfg.components != [ ] then
      "-i ${lib.concatStringsSep " " cfg.components}"
    else
      "";

  # $1 = current home-manager generation path (empty = always sync)
  dotfilesScript = pkgs.writeShellScript "dotfiles-setup" ''
    set -euo pipefail
    # Nix values are defaults so the script can be exercised standalone
    : "''${DOTFILES_DIR:=${cfg.directory}}"
    : "''${REPO_URL:=${cfg.repoUrl}}"
    : "''${BRANCH:=${cfg.branch}}"
    GEN="''${1:-}"
    STAMP="$DOTFILES_DIR/.git/dotfiles-synced-gen"
    NET_TIMEOUT=60
    LOG="''${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles-sync.log"

    # Quiet activation: everything below goes to the last-run log
    mkdir -p "$(dirname "$LOG")"
    exec > "$LOG" 2>&1
    echo "dotfiles-setup $(date '+%Y-%m-%d %H:%M:%S') gen=''${GEN:-<none>}"

    # Activation has no tty: never prompt, never hang
    export GIT_TERMINAL_PROMPT=0
    export GIT_SSH_COMMAND="${pkgs.openssh}/bin/ssh -oBatchMode=yes"

    log()  { echo "dotfiles: $*"; }
    warn() { echo "dotfiles: WARN: $*" >&2; }
    stamp() { [ -n "$GEN" ] && echo "$GEN" > "$STAMP" 2>/dev/null || true; }

    if [ ! -d "$DOTFILES_DIR" ]; then
      log "cloning $REPO_URL ($BRANCH) into $DOTFILES_DIR"
      if ! ${pkgs.coreutils}/bin/timeout "$NET_TIMEOUT" \
          ${gitBin} clone --quiet --branch "$BRANCH" "$REPO_URL" "$DOTFILES_DIR"; then
        warn "clone failed (offline?); nothing linked, retrying on next rebuild"
        exit 0
      fi
      stamp
    elif [ -n "$GEN" ] && [ "$(cat "$STAMP" 2>/dev/null || true)" = "$GEN" ]; then
      log "generation unchanged, skipping pull"
    else
      stamp
      stashes_before=$(${gitBin} -C "$DOTFILES_DIR" stash list | wc -l)
      if ${pkgs.coreutils}/bin/timeout "$NET_TIMEOUT" \
          ${gitBin} -C "$DOTFILES_DIR" pull --quiet --ff-only --autostash; then
        log "pulled $(${gitBin} -C "$DOTFILES_DIR" rev-parse --short HEAD)"
        if [ "$(${gitBin} -C "$DOTFILES_DIR" stash list | wc -l)" -gt "$stashes_before" ]; then
          # git leaves conflict markers in the tree on autostash failure;
          # the local edits are already in stash@{0}, so restore upstream
          ${gitBin} -C "$DOTFILES_DIR" reset --hard --quiet
          warn "local changes conflicted with upstream and were parked in git stash@{0}"
        fi
      else
        warn "pull failed (offline or diverged); keeping current checkout"
      fi
    fi

    INSTALL_SCRIPT="$DOTFILES_DIR/getdots.sh"
    if [ ! -f "$INSTALL_SCRIPT" ]; then
      warn "getdots.sh not found at $INSTALL_SCRIPT"
      exit 0
    fi
    ${pkgs.bash}/bin/bash "$INSTALL_SCRIPT" ${installArgs} \
      || warn "getdots.sh failed (see log above)"
  '';
in
{
  options.dotfiles = {
    enable = lib.mkEnableOption "dotfiles management via git clone";

    repoUrl = lib.mkOption {
      type = lib.types.str;
      default = defaultRepoUrl;
      description = ''
        Git repository URL for dotfiles. Defaults to HTTPS so fresh hosts
        without SSH keys can still clone a public repo.
      '';
      example = "https://github.com/username/dotfiles.git";
    };

    directory = lib.mkOption {
      type = lib.types.str;
      default = defaultDir;
      description = "Local directory to clone dotfiles into";
    };

    branch = lib.mkOption {
      type = lib.types.str;
      default = "main";
      description = "Git branch to checkout";
    };

    installAll = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install all dotfiles by running getdots.sh without arguments.
        When true, the 'components' option is ignored.
        Set to false to install only specific components.
      '';
    };

    components = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      apply = lib.unique;
      description = ''
        List of dotfile components to install with -i flag.
        Only used when installAll = false.
        Multiple definitions are merged.
      '';
      example = [
        "nvim"
        "p10k"
      ];
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.directory != "" && cfg.directory != "/";
        message = "dotfiles.directory must be a non-root path";
      }
      {
        assertion = cfg.directory != config.home.homeDirectory;
        message = "dotfiles.directory must not be the home directory itself";
      }
    ];

    warnings = lib.optional (
      cfg.installAll && cfg.components != [ ]
    ) "dotfiles.components is ignored while dotfiles.installAll = true";

    # $newGenPath is defined by home-manager's activation script; it changes
    # on every rebuild but not when the NixOS boot service re-runs activation.
    home.activation.setupDotfiles = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${dotfilesScript} "$newGenPath" || true
    '';
  };
}
