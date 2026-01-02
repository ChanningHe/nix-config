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

  # Use user's configured git package to avoid conflicts
  gitBin =
    if config.programs.git.enable then
      "${config.programs.git.package}/bin/git"
    else
      "${pkgs.git}/bin/git";

  # Default dotfiles directory
  defaultDir = "${config.home.homeDirectory}/.config/dotfiles";

  defaultRepoUrl = "git@github.com:ChanningHe/dotfiles.git";

  # Build install.sh arguments
  installArgs =
    if cfg.components == [ ] then
      "" # Install all
    else
      "-i ${lib.concatStringsSep " " cfg.components}";
in
{
  options.dotfiles = {
    enable = lib.mkEnableOption "dotfiles management via git clone";

    repoUrl = lib.mkOption {
      type = lib.types.str;
      default = defaultRepoUrl;
      description = "Git repository URL for dotfiles";
      example = "git@github.com:username/dotfiles.git";
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

    components = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      apply = lib.unique; # Deduplicate merged lists
      description = "List of dotfile components to install (empty = all). Multiple definitions are merged.";
      example = [
        "nvim"
        "p10k"
      ];
    };
  };

  config = lib.mkIf cfg.enable {
    # Clone and install dotfiles
    home.activation.setupDotfiles = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      DOTFILES_DIR="${cfg.directory}"
      REPO_URL="${cfg.repoUrl}"
      BRANCH="${cfg.branch}"

      # Clone if not exists, or update if exists
      if [ ! -d "$DOTFILES_DIR/.git" ]; then
        $DRY_RUN_CMD echo "Cloning dotfiles repository..."
        $DRY_RUN_CMD mkdir -p "$(dirname "$DOTFILES_DIR")"
        $DRY_RUN_CMD ${gitBin} clone --branch "$BRANCH" "$REPO_URL" "$DOTFILES_DIR" || {
          echo "Warning: Failed to clone dotfiles. Clone manually:"
          echo "  git clone $REPO_URL $DOTFILES_DIR"
          exit 0
        }
      else
        $DRY_RUN_CMD echo "Updating dotfiles repository..."
        # Check for uncommitted changes
        if ${gitBin} -C "$DOTFILES_DIR" diff --quiet && ${gitBin} -C "$DOTFILES_DIR" diff --cached --quiet; then
          $DRY_RUN_CMD ${gitBin} -C "$DOTFILES_DIR" pull --ff-only || {
            echo "Warning: Failed to update dotfiles (non-fast-forward). Manual intervention needed."
          }
        else
          echo "Warning: Dotfiles has uncommitted changes, skipping update."
          echo "  cd $DOTFILES_DIR && git status"
        fi
      fi

      # Run getdots.sh
      INSTALL_SCRIPT="$DOTFILES_DIR/getdots.sh"
      if [ -x "$INSTALL_SCRIPT" ]; then
        $DRY_RUN_CMD echo "Running dotfiles getdots.sh ${installArgs}..."
        $DRY_RUN_CMD "$INSTALL_SCRIPT" ${installArgs}
      else
        echo "Warning: getdots.sh not found or not executable at $INSTALL_SCRIPT"
      fi
    '';
  };
}
