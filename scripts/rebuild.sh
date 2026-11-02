#!/usr/bin/env bash
# shellcheck disable=SC2086
#
# This script is used to rebuild the system configuration for the current host.
#
# SC2086 is ignored because we purposefully pass some values as a set of arguments, so we want the splitting to happen
set -euo pipefail

function red() {
	echo -e "\x1B[31m[!] $1 \x1B[0m"
	if [ -n "${2-}" ]; then
		echo -e "\x1B[31m[!] $($2) \x1B[0m"
	fi
}
function green() {
	echo -e "\x1B[32m[+] $1 \x1B[0m"
	if [ -n "${2-}" ]; then
		echo -e "\x1B[32m[+] $($2) \x1B[0m"
	fi
}

function yellow() {
	echo -e "\x1B[33m[*] $1 \x1B[0m"
	if [ -n "${2-}" ]; then
		echo -e "\x1B[33m[*] $($2) \x1B[0m"
	fi
}

HOST=$(hostname)
ACTION="switch"
# Only pin nh to a host when one is given; otherwise nh picks the local one.
nh_host_args=()

if [[ ${1-} == "build" ]]; then
	ACTION="build"
elif [[ -n ${1-} ]]; then
	HOST=$1
	nh_host_args=(-H "$HOST")
fi
switch_args="--show-trace --flake .#$HOST $ACTION"

os=$(uname -s)
if [ "$os" == "Darwin" ]; then
	# FIXME: This might not have to be darwin specific

	# FIXME: This will break if HM tries to create the file. We should use environment variables instead
	mkdir -p ~/.config/nix || true
	CONF=~/.config/nix/nix.conf
	if [ ! -f $CONF ]; then
		# Enable nix-command and flakes to bootstrap
		cat <<-EOF >$CONF
			experimental-features = nix-command flakes
		EOF
	fi

	# Do some darwin pre-installation for bootstrapping
	if ! which git &>/dev/null; then
		echo "Installing xcode tools"
		xcode-select --install
	fi

	# https://docs.brew.sh/Installation
	if [ ! -e /opt/homebrew/bin/brew ]; then
		echo "Installing rosetta"
		# This is required for emulation of x86_64 binaries, so let's just
		# assume if they didn't install brew yet, they need this
		softwareupdate --install-rosetta --agree-to-license
		echo "Installing homebrew"
		export NONINTERACTIVE=1
		/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
	fi

	green "====== ${ACTION^^} ======"
	if command -v nh &>/dev/null; then
		nh darwin $ACTION . "${nh_host_args[@]}" -- --show-trace
	else
		# Fallback: bootstrap or use darwin-rebuild directly
		if ! which darwin-rebuild &>/dev/null; then
			nix build --show-trace .#darwinConfigurations."$HOST".system
			sudo ./result/sw/bin/darwin-rebuild $switch_args
		else
			sudo darwin-rebuild $switch_args
		fi
	fi
else
	green "====== ${ACTION^^} ======"
	if command -v nh &>/dev/null; then
		nh os $ACTION . "${nh_host_args[@]}" -- --show-trace
	else
		sudo nixos-rebuild $ACTION --show-trace --flake .#"$HOST"
	fi
fi

# set -e: reaching this point means the rebuild above succeeded.
if [ "$ACTION" == "build" ]; then
	green "====== BUILD COMPLETE ======"
	green "Build successful (not switched)"
	exit 0
fi

green "====== POST-REBUILD ======"
green "Rebuilt successfully"

# Check if there are any pending changes that would affect the build succeeding.
if git diff --exit-code >/dev/null && git diff --staged --exit-code >/dev/null; then
	# Check if the current commit has a buildable tag
	if [[ $(git tag --points-at HEAD) == *buildable* ]]; then
		yellow "Current commit is already tagged as buildable"
	else
		git tag buildable-"$(date +%Y%m%d%H%M%S)" -m ''
		green "Tagged current commit as buildable"
	fi
else
	yellow "WARN: There are pending changes that would affect the build succeeding. Commit them before tagging"
fi
