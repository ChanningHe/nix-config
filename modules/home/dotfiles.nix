# Dotfiles Configuration Module
# This module clones the dotfiles repository and runs getdots.sh
#
# The actual dotfile mappings are defined in dotfiles/dotfiles.toml
# This keeps the Nix module simple and the config in one place (SSoT)
#
# Two-stage setup:
#   1. home.activation: tries clone/update during nixos-rebuild switch
#   2. systemd oneshot: retries on first login if activation failed (e.g. no SSH key yet)
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
  defaultRepoUrl = "git@github.com:ChanningHe/dotfiles.git";

  installArgs =
    if cfg.installAll then
      ""
    else if cfg.components != [ ] then
      "-i ${lib.concatStringsSep " " cfg.components}"
    else
      "";

  sshBin = "${pkgs.openssh}/bin/ssh";

  # Shared shell logic used by both activation and systemd service
  dotfilesScript = pkgs.writeShellScript "dotfiles-setup" ''
    set -euo pipefail
    DOTFILES_DIR="${cfg.directory}"
    REPO_URL="${cfg.repoUrl}"
    BRANCH="${cfg.branch}"

    # Verify SSH connectivity to GitHub before attempting clone
    ssh_check() {
      ${sshBin} -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
        -T git@github.com 2>&1 | grep -qi "successfully authenticated"
    }

    if ! ssh_check; then
      echo "dotfiles: SSH to github.com not available (no key loaded?). Skipping."
      exit 1
    fi

    # Clone or update
    if [ ! -d "$DOTFILES_DIR/.git" ]; then
      echo "dotfiles: Cloning $REPO_URL ..."
      mkdir -p "$(dirname "$DOTFILES_DIR")"
      ${gitBin} clone --branch "$BRANCH" "$REPO_URL" "$DOTFILES_DIR"
    else
      echo "dotfiles: Updating (pull --ff-only) ..."
      if ${gitBin} -C "$DOTFILES_DIR" diff --quiet && ${gitBin} -C "$DOTFILES_DIR" diff --cached --quiet; then
        ${gitBin} -C "$DOTFILES_DIR" pull --ff-only || echo "dotfiles: pull failed (non-fast-forward), skipping."
      else
        echo "dotfiles: Uncommitted changes, skipping pull."
      fi
    fi

    # Run getdots.sh
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
    # Stage 1: try during nixos-rebuild switch (works when SSH is already available)
    home.activation.setupDotfiles = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${dotfilesScript} || echo "dotfiles: activation skipped, will retry on login via systemd."
    '';

    # Stage 2: retry on first user login (SSH agent + keys should be available)
    systemd.user.services.dotfiles-setup = {
      Unit = {
        Description = "Clone/update dotfiles repository";
        After = [ "ssh-agent.service" ];
        ConditionPathIsDirectory = "!${cfg.directory}/.git";
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${dotfilesScript}";
        Restart = "on-failure";
        RestartSec = "10s";
        RestartMaxDelaySec = "60s";
        # Inherit SSH_AUTH_SOCK from user session
        Environment = "SSH_AUTH_SOCK=%t/ssh-agent";
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
    };
  };
}
