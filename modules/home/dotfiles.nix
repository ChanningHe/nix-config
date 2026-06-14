# Dotfiles Configuration Module
# This module clones the dotfiles repository and runs getdots.sh
#
# The actual dotfile mappings are defined in dotfiles/dotfiles.toml
# This keeps the Nix module simple and the config in one place (SSoT)
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

  dotfilesScript = pkgs.writeShellScript "dotfiles-setup" ''
    set -euo pipefail
    DOTFILES_DIR="${cfg.directory}"
    REPO_URL="${cfg.repoUrl}"
    BRANCH="${cfg.branch}"

    clone_fresh() {
      echo "dotfiles: Cloning $REPO_URL ..."
      rm -rf "$DOTFILES_DIR"
      mkdir -p "$(dirname "$DOTFILES_DIR")"
      ${gitBin} clone --branch "$BRANCH" "$REPO_URL" "$DOTFILES_DIR"
    }

    if [ ! -d "$DOTFILES_DIR/.git" ]; then
      clone_fresh
    else
      # Anything `git status` can't read = broken checkout.
      worktree_status=$(${gitBin} -C "$DOTFILES_DIR" status --porcelain 2>/dev/null || echo BROKEN)
      case "$worktree_status" in
        BROKEN)
          echo "dotfiles: Broken checkout at $DOTFILES_DIR, re-cloning ..."
          clone_fresh
          ;;
        "")
          echo "dotfiles: Updating (pull --ff-only) ..."
          if ! ${gitBin} -C "$DOTFILES_DIR" pull --ff-only; then
            # Clean worktree + pull failed = upstream rewrote history,
            # branch was renamed, or remote URL changed. Recover by re-cloning.
            echo "dotfiles: pull failed on clean worktree, re-cloning ..."
            clone_fresh
          fi
          ;;
        *)
          echo "dotfiles: Local changes present, skipping pull."
          ;;
      esac
    fi

    INSTALL_SCRIPT="$DOTFILES_DIR/getdots.sh"
    if [ -x "$INSTALL_SCRIPT" ]; then
      echo "dotfiles: Running getdots.sh ${installArgs} ..."
      "$INSTALL_SCRIPT" ${installArgs}
    else
      echo "dotfiles: getdots.sh not found at $INSTALL_SCRIPT"
    fi
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
    home.activation.setupDotfiles = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${dotfilesScript} || echo "dotfiles: setup failed (see log above)."
    '';
  };
}
