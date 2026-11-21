#!/usr/bin/env bash
#
# Wait until the attic cache serves <host>'s current system closure, so hosts
# deployed afterwards substitute from it instead of rebuilding. The cache is an
# optimization: on timeout we warn and let the caller carry on.
#
# Usage: wait-attic.sh <host>   (ATTIC_WAIT_TIMEOUT overrides the 600s limit)
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/helpers.sh"

host="${1:?usage: wait-attic.sh <host>}"
timeout="${ATTIC_WAIT_TIMEOUT:-600}"
interval=10
netrc="$HOME/.config/attic/netrc"

# shellcheck disable=SC2016 # Nix expression, not shell
url=$(nix eval --raw ".#nixosConfigurations.${host}.config" --apply '
  c: "https://${c.hostSpec.serviceInfo.attic.endpoint}/${builtins.substring 0 32 (baseNameOf c.system.build.toplevel.outPath)}.narinfo"
') || {
	yellow "could not resolve ${host}'s attic narinfo; skipping wait"
	exit 0
}

# curl rejects a missing --netrc-file even with --netrc-optional
auth=()
[ -r "$netrc" ] && auth=(--netrc-file "$netrc")

blue "Waiting for ${host}'s system in attic: ${url}"
deadline=$((SECONDS + timeout))
until curl -fsS -o /dev/null --max-time 5 ${auth[@]+"${auth[@]}"} "$url" 2>/dev/null; do
	if ((SECONDS >= deadline)); then
		yellow "attic not ready after ${timeout}s; continuing without a warm cache"
		exit 0
	fi
	sleep "$interval"
done
green "attic serves ${host}'s system"
