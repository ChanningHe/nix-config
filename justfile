SOPS_FILE := "../nix-secrets/.sops.yaml"

# Define path to helpers
export HELPERS_PATH := justfile_directory() + "/scripts/helpers.sh"

# default recipe to display help information
default:
  @just --list

# Update commonly changing flakes and prep for a rebuild
rebuild-pre: update-nix-secrets
  @git add --intent-to-add .

# Run post-rebuild checks, like if sops is running properly afterwards
rebuild-post: check-sops

# Run a flake check on the config and installer
check ARGS="":
	NIXPKGS_ALLOW_UNFREE=1 REPO_PATH=$(pwd) nix flake check --impure --keep-going --show-trace {{ARGS}}
	cd nixos-anywhere && NIXPKGS_ALLOW_UNFREE=1 REPO_PATH=$(pwd) nix flake check --impure --keep-going --show-trace {{ARGS}}

# Rebuild the system
rebuild: rebuild-pre && rebuild-post
  # NOTE: Add --option eval-cache false if you end up caching a failure you can't get around
  scripts/rebuild.sh

# Build only without switching (dry run)
build: rebuild-pre
  scripts/rebuild.sh build

# Rebuild the system and run a flake check
rebuild-full: rebuild-pre && rebuild-post
  scripts/rebuild.sh
  just check

# Rebuild the system and run a flake check
rebuild-trace: rebuild-pre && rebuild-post
  scripts/rebuild.sh trace
  just check

# Update the flake
update:
  nix flake update

# Update and then rebuild
rebuild-update: update rebuild

# Git diff there entire repo expcept for flake.lock
diff:
  git diff ':!flake.lock'

# Generate a new age key
age-key:
  nix-shell -p age --run "age-keygen"

# Check if sops-nix activated successfully
check-sops:
  scripts/check-sops.sh

# Scaffold a new NixOS host (interactive)
new-host *ARGS:
  scripts/new-host.sh {{ARGS}}

# Update nix-secrets flake
update-nix-secrets:
  @[ -d ../nix-secrets ] && (cd ../nix-secrets && git fetch && (git rebase > /dev/null 2>&1 || true)) || true
  nix flake update nix-secrets --timeout 5

# Build an iso image for installing new systems and create a symlink for qemu usage
iso:
  # If we dont remove this folder, libvirtd VM doesnt run with the new iso...
  rm -rf result
  nix build --impure .#nixosConfigurations.iso.config.system.build.isoImage && ln -sf result/iso/*.iso latest.iso

# Install the latest iso to a flash drive
iso-install DRIVE: iso
  sudo dd if=$(eza --sort changed result/iso/*.iso | tail -n1) of={{DRIVE}} bs=4M status=progress oflag=sync

# Configure a drive password using disko
disko DRIVE PASSWORD:
  echo "{{PASSWORD}}" > /tmp/disko-password
  sudo nix --experimental-features "nix-command flakes" run github:nix-community/disko -- \
    --mode disko \
    disks/btrfs-luks-impermanence-disko.nix \
    --arg disk '"{{DRIVE}}"' \
    --arg password '"{{PASSWORD}}"'
  rm /tmp/disko-password

# Copy all the config files to the remote host
sync USER HOST PATH:
	rsync -av --filter=':- .gitignore' -e "ssh -l {{USER}} -oport=22" . {{USER}}@{{HOST}}:{{PATH}}/nix-config

# Run nixos-rebuild on the remote host
build-host HOST:
	NIX_SSHOPTS="-p22" nixos-rebuild --target-host {{HOST}} --use-remote-sudo --show-trace --impure --flake .#"{{HOST}}" switch

# Called by the rekey recipe
sops-rekey:
  cd ../nix-secrets && for file in $(ls secrets/*.yaml); do \
    sops updatekeys -y $file; \
  done

# Update all keys in secrets/*.yaml files in nix-secrets to match the creation rules keys
rekey: sops-rekey
  @echo "Rekey complete. Remember to commit and push nix-secrets."

# Update an age key anchor or add a new one
sops-update-age-key FIELD KEYNAME KEY:
    #!/usr/bin/env bash
    source {{HELPERS_PATH}}
    sops_update_age_key {{FIELD}} {{KEYNAME}} {{KEY}}

# Update an existing user age key anchor or add a new one
sops-update-user-age-key USER HOST KEY:
  just sops-update-age-key users {{USER}}_{{HOST}} {{KEY}}

# Update an existing host age key anchor or add a new one
sops-update-host-age-key HOST KEY:
  just sops-update-age-key hosts {{HOST}} {{KEY}}

# Automatically create creation rules entries for a <host>.yaml file for host-specific secrets
sops-add-host-creation-rules USER HOST:
    #!/usr/bin/env bash
    source {{HELPERS_PATH}}
    sops_add_host_creation_rules "{{USER}}" "{{HOST}}"

# Automatically create creation rules entries for a shared.yaml file for shared secrets
sops-add-shared-creation-rules USER HOST:
    #!/usr/bin/env bash
    source {{HELPERS_PATH}}
    sops_add_shared_creation_rules "{{USER}}" "{{HOST}}"

# Automatically add the host and user keys to creation rules for shared.yaml and <host>.yaml
sops-add-creation-rules USER HOST:
    just sops-add-host-creation-rules {{USER}} {{HOST}} && \
    just sops-add-shared-creation-rules {{USER}} {{HOST}}

# Push current system closure to Attic cache
attic-push:
    #!/usr/bin/env bash
    # Determine the system profile path based on OS
    if [[ "$(uname)" == "Darwin" ]]; then
        PROFILE_PATH="/nix/var/nix/profiles/system"
    else
        PROFILE_PATH="/run/current-system"
    fi

    if [[ -L "$PROFILE_PATH" ]]; then
        echo "Pushing current system closure to homielab cache..."
        attic push homielab $(readlink -f "$PROFILE_PATH")
    else
        echo "Error: System profile not found at $PROFILE_PATH"
        exit 1
    fi

# Push specific store paths to Attic cache
attic-push-path PATHS:
    attic push homielab {{PATHS}}

# ========= Standalone Home-Manager (non-NixOS Linux) =========

# Build standalone home-manager config without switching (dry run)
hm-build TARGET="channinghe@standalone-linux":
  nix build .#homeConfigurations.{{TARGET}}.activationPackage --show-trace

# Deploy standalone home-manager config on current machine
hm-switch TARGET="channinghe@standalone-linux":
  nix run home-manager/release-25.11 -- switch -b bk --flake .#{{TARGET}}

# Deploy with verbose trace for debugging
hm-switch-trace TARGET="channinghe@standalone-linux":
  nix run home-manager/release-25.11 -- switch -b bk --flake .#{{TARGET}} --show-trace

# Deploy standalone home-manager to a remote host via SSH
hm-remote USER HOST TARGET="channinghe@standalone-linux" PATH="~/nix-src/nix-config":
  ssh {{USER}}@{{HOST}} "cd {{PATH}} && nix run home-manager/release-25.11 -- switch -b bk --flake .#{{TARGET}}"

reset-repo:
  git fetch origin && git reset --hard origin/master
