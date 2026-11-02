#!/usr/bin/env bash
set -euo pipefail

# spawn — provision a NixOS host end to end.
#
# Detects the current repo + target state and runs only the steps that are
# still needed, so it is idempotent and resumable: re-running after a failure
# picks up where it left off.
#
# Steps:
#   scaffold  host config from template (disk.layout, network, hostId)
#   secrets   generate SSH host key -> sops
#   disk      discover the target disk + NIC MAC, back-fill the config
#   install   nixos-anywhere: disko + nixos-facter + install + reboot
#
# install uses the full host config (the main flake), so the rebooted system is
# already complete — there is no deploy step. To UPDATE an existing host later,
# use `just deploy <host>` (deploy-rs, auto-rollback).
#
# Logic that Nix can express lives in Nix (see lib.custom.bootDiskLayout in
# lib/boot-disk.nix); this script is only orchestration.

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

###############################################################################
# Dependency check
###############################################################################

REQUIRED_TOOLS=(git nix ssh ssh-keygen ssh-to-age sops yq jq rsync nix-instantiate)
function check_dependencies() {
	local missing=()
	for cmd in "${REQUIRED_TOOLS[@]}"; do
		command -v "$cmd" &>/dev/null || missing+=("$cmd")
	done
	if [ ${#missing[@]} -gt 0 ]; then
		red "ERROR: Missing required tools: ${missing[*]}"
		red "Are you inside the nix dev shell? Run: nix develop"
		exit 1
	fi
}

# Optional nicer prompts via charm gum.
HAS_GUM=0
command -v gum &>/dev/null && HAS_GUM=1

###############################################################################
# Defaults & globals
###############################################################################

host=""
target_ip=""
ssh_port=${BOOTSTRAP_SSH_PORT-22}
target_user=${BOOTSTRAP_USER-channinghe}
disk_layout=""
target_system="x86_64-linux"
build_strategy="no-external" # no-external | no-remote | on-target
opt_ip4="" opt_gateway4="" opt_dns="" opt_hostid=""
assume_yes=0
force_wipe=0
dry_run=0
only_step=""
from_step=""
declare -a skip_steps=()

git_root=$(git rev-parse --show-toplevel)
nix_secrets_dir=${NIX_SECRETS_DIR:-"${git_root}"/../nix-secrets}
host_template="${git_root}/hosts/host-template.nix.placeholder"
home_template="${git_root}/home/channinghe/home-template.nix.placeholder"
network_nix="${nix_secrets_dir}/nix/network.nix"

# Detected state (filled by detect_*).
REPO_SCAFFOLDED=0 REPO_SECRETS=0 REPO_FACTER=0 REPO_DISK_SET=0
TARGET_STATE="UNKNOWN" # UNREACHABLE|NON_NIXOS|INSTALLER|INSTALLED_THIS|INSTALLED_OTHER

###############################################################################
# Usage
###############################################################################

function help_and_exit() {
	cat <<EOF

spawn — provision a NixOS host (idempotent, resumable).

USAGE: $0 <hostname> [-d <ip>] [OPTIONS]

REQUIRED:
  <hostname>                 Host name (matches hosts/nixos/<hostname>)

CONNECTION:
  -d, --destination <ip>     Target IP/host (needed for disk/install)
  --port <port>              SSH port (default: 22)
  -u, --user <name>          Target user (default: ${target_user})

SCAFFOLD (else prompted):
  --disk-layout <ext4|btrfs|zfs|zfs-mirror>
  --system <x86_64-linux|aarch64-linux>
  --ip4 <addr>  --gateway4 <addr>  --dns <addr>  --host-id <hex>

INSTALL BUILD STRATEGY:
  --build-strategy <mode>    Where/how nixos-anywhere builds (default no-external)
                               no-external = build local, skip external-builders
                                             (nix-vz-builder), use ssh builders
                               no-remote   = build local, skip ssh builders
                               on-target   = build on the target (--build-on remote)

STEP CONTROL:
  --only <step>              Run a single step
  --from <step>              Run from this step to the end
  --skip <step>              Skip a step (repeatable)
                             steps: scaffold secrets disk install

OTHER:
  -y, --yes                  Don't ask for confirmation
  --force-wipe               With -y: allow install on a target that is not
                             the NixOS installer (running OS gets wiped)
  --dry-run                 Detect + print plan only
  --debug                    set -x
  -h, --help

EXAMPLES:
  $0 Mola -d 10.40.20.101 --disk-layout ext4
  $0 Mola -d 10.40.20.101 --system aarch64-linux --disk-layout ext4
  $0 Mola --only scaffold
  $0 Mola -d 10.40.20.101 --from install
EOF
	exit "${1:-0}"
}

function normalize_system() {
	case "$1" in
	x86_64-linux | amd64) echo "x86_64-linux" ;;
	aarch64-linux | arm64) echo "aarch64-linux" ;;
	*) return 1 ;;
	esac
}

###############################################################################
# Argument parsing
###############################################################################

while [[ $# -gt 0 ]]; do
	case "$1" in
	-h | --help) help_and_exit 0 ;;
	-d | --destination)
		target_ip=$2
		shift 2
		;;
	--port)
		ssh_port=$2
		shift 2
		;;
	-u | --user)
		target_user=$2
		shift 2
		;;
	--disk-layout)
		disk_layout=$2
		shift 2
		;;
	--system)
		target_system=$2
		shift 2
		;;
	--build-strategy)
		build_strategy=$2
		shift 2
		;;
	--ip4)
		opt_ip4=$2
		shift 2
		;;
	--gateway4)
		opt_gateway4=$2
		shift 2
		;;
	--dns)
		opt_dns=$2
		shift 2
		;;
	--host-id)
		opt_hostid=$2
		shift 2
		;;
	--only)
		only_step=$2
		shift 2
		;;
	--from)
		from_step=$2
		shift 2
		;;
	--skip)
		skip_steps+=("$2")
		shift 2
		;;
	-y | --yes)
		assume_yes=1
		shift
		;;
	--force-wipe)
		force_wipe=1
		shift
		;;
	--dry-run)
		dry_run=1
		shift
		;;
	--debug)
		set -x
		shift
		;;
	-*)
		red "Unknown option: $1"
		help_and_exit 1
		;;
	*)
		if [ -z "$host" ]; then host=$1; else
			red "Unexpected argument: $1"
			help_and_exit 1
		fi
		shift
		;;
	esac
done

requested_system=$target_system
if ! target_system=$(normalize_system "$requested_system"); then
	red "ERROR: invalid --system '${requested_system}' (x86_64-linux | aarch64-linux)"
	exit 1
fi

[ -z "$host" ] && {
	red "ERROR: hostname is required"
	help_and_exit 1
}
case "$build_strategy" in
no-external | no-remote | on-target) ;;
*)
	red "ERROR: invalid --build-strategy '$build_strategy' (no-external | no-remote | on-target)"
	exit 1
	;;
esac
check_dependencies

# Private scratch root for key material, removed on any exit. Per-function
# RETURN traps miss `exit` and set -e aborts, leaking decrypted host keys.
spawn_tmp=$(mktemp -d -p /dev/shm 2>/dev/null || mktemp -d)
trap 'rm -rf "$spawn_tmp"' EXIT
trap 'exit 130' INT TERM

###############################################################################
# Small helpers
###############################################################################

# ask <prompt> [default] -> echoes answer on stdout (gum if available, else read).
# The prompt goes to stderr so it stays visible when called via $(ask ...).
function ask() {
	local prompt="$1" default="${2:-}" ans
	if [ "$HAS_GUM" -eq 1 ]; then
		ans=$(gum input --prompt "$prompt " --placeholder "$default" --value "$default")
	else
		echo -en "\x1B[34m[?] ${prompt}${default:+ [${default}]}: \x1B[0m" >&2
		read -r ans
		ans=${ans:-$default}
	fi
	echo "$ans"
}

function confirm() {
	[ "$assume_yes" -eq 1 ] && return 0
	if [ "$HAS_GUM" -eq 1 ]; then gum confirm "$1"; else yes_or_no "$1"; fi
}

# Run a read-only probe on the target, non-interactive. Tries the primary user
# first (the installed system disables root SSH), then root (installer /
# nixos-anywhere environments where root is the only account).
# SC2029: the command in "$@" is built locally and intentionally sent to the
# remote shell — client-side expansion is what we want here.
# shellcheck disable=SC2029
function tssh() {
	local opts=(-p "$ssh_port" -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new
		-o UserKnownHostsFile=/dev/null -o BatchMode=yes)
	ssh "${opts[@]}" "${target_user}@${target_ip}" "$@" 2>/dev/null && return 0
	ssh "${opts[@]}" "root@${target_ip}" "$@" 2>/dev/null
}

# step_enabled <name> — honour --only / --from / --skip and the plan.
declare -A PLAN=()
function step_enabled() { [ "${PLAN[$1]:-0}" -eq 1 ]; }

###############################################################################
# State detection
###############################################################################

function detect_repo_state() {
	[ -f "${git_root}/hosts/nixos/${host}/default.nix" ] && REPO_SCAFFOLDED=1
	[ -f "${git_root}/hosts/nixos/${host}/facter.json" ] && REPO_FACTER=1

	# secrets: can sops decrypt this host's ssh host key?
	local secret_file="${nix_secrets_dir}/secrets/${host}.yaml"
	if [ -f "$secret_file" ] &&
		sops --config "${nix_secrets_dir}/.sops.yaml" -d \
			--extract '["keys"]["ssh_host_ed25519_key"]' "$secret_file" >/dev/null 2>&1; then
		REPO_SECRETS=1
	fi

	# disk device(s) already pinned in the bootDiskLayout call? zfs-mirror also
	# needs disk2, otherwise lib/boot-disk.nix silently falls back to /dev/vdb.
	if [ "$REPO_SCAFFOLDED" -eq 1 ] && disk_pinned disk &&
		{ [ "$(host_layout)" != "zfs-mirror" ] || disk_pinned disk2; }; then
		REPO_DISK_SET=1
	fi
}

function detect_target_state() {
	[ -z "$target_ip" ] && {
		TARGET_STATE="UNKNOWN"
		return
	}
	if ! tssh true; then
		TARGET_STATE="UNREACHABLE"
		return
	fi
	local rootfs remote_host
	rootfs=$(tssh "findmnt -no FSTYPE /" || true)
	if ! tssh "command -v nixos-version" >/dev/null; then
		TARGET_STATE="NON_NIXOS"
		return
	fi
	case "$rootfs" in
	tmpfs | overlay | squashfs)
		TARGET_STATE="INSTALLER"
		return
		;;
	esac
	remote_host=$(tssh "hostname" || true)
	if [ "$remote_host" = "$host" ]; then TARGET_STATE="INSTALLED_THIS"; else TARGET_STATE="INSTALLED_OTHER"; fi
}

###############################################################################
# Plan
###############################################################################

# Decide which steps still need to run, honouring filters.
function build_plan() {
	local all=(scaffold secrets disk install) s
	# Default "pending" decision from detected state. install uses the full
	# config, so there is no separate deploy step — the booted system is final.
	# (Updating an existing host later is `just deploy <host>`.)
	local -A want=()
	want[scaffold]=$((REPO_SCAFFOLDED ? 0 : 1))
	want[secrets]=$((REPO_SECRETS ? 0 : 1))
	want[disk]=$((REPO_DISK_SET ? 0 : 1))
	want[install]=$([ "$TARGET_STATE" = "INSTALLED_THIS" ] && echo 0 || echo 1)

	for s in "${all[@]}"; do
		PLAN[$s]=${want[$s]}
		# --only overrides everything.
		if [ -n "$only_step" ]; then PLAN[$s]=$([ "$s" = "$only_step" ] && echo 1 || echo 0); fi
	done

	# --from <s>: enable s..end (subject to nothing else).
	if [ -n "$from_step" ]; then
		local seen=0
		for s in "${all[@]}"; do
			[ "$s" = "$from_step" ] && seen=1
			PLAN[$s]=$seen
		done
	fi
	# --skip
	for s in "${skip_steps[@]}"; do PLAN[$s]=0; done
}

function print_state_and_plan() {
	echo
	blue "════════ spawn: ${host} ════════"
	echo "  repo:    scaffold $([ $REPO_SCAFFOLDED = 1 ] && echo ✓ || echo ✗)   secrets $([ $REPO_SECRETS = 1 ] && echo ✓ || echo ✗)   disk-pinned $([ $REPO_DISK_SET = 1 ] && echo ✓ || echo ✗)   facter $([ $REPO_FACTER = 1 ] && echo ✓ || echo ✗)"
	echo "  target:  ${target_ip:-N/A}   state = ${TARGET_STATE}"
	echo
	blue "Plan:"
	local s desc
	for s in scaffold secrets disk install; do
		case "$s" in
		scaffold) desc="host config from template" ;;
		secrets) desc="ssh host key -> sops" ;;
		disk) desc="discover disk + NIC MAC, back-fill config" ;;
		install) desc="nixos-anywhere: disko + facter + install + reboot (full config)  ⚠ WIPES DISK" ;;
		esac
		if step_enabled "$s"; then green "  [run]  ${s} — ${desc}"; else echo "  [skip] ${s}"; fi
	done
	echo
}

###############################################################################
# Step: scaffold
###############################################################################

function step_scaffold() {
	local host_dir="${git_root}/hosts/nixos/${host}"
	local home_file="${git_root}/home/channinghe/${host}.nix"
	if [ -d "$host_dir" ]; then
		yellow "scaffold: hosts/nixos/${host} exists — skipping."
		return 0
	fi
	[ -f "$host_template" ] || {
		red "Host template missing: $host_template"
		exit 1
	}
	[ -f "$home_template" ] || {
		red "Home template missing: $home_template"
		exit 1
	}

	[ -z "$disk_layout" ] && disk_layout=$(ask "Disk layout (ext4/btrfs/zfs/zfs-mirror)" "ext4")
	local ip4 gw4 dns hostid
	ip4=${opt_ip4:-$(ask "IPv4 address (e.g. 10.1.10.100)")}
	[ -z "$ip4" ] && {
		red "IPv4 required"
		exit 1
	}
	gw4=${opt_gateway4:-$(ask "IPv4 gateway" "10.1.10.1")}
	dns=${opt_dns:-$(ask "DNS server" "10.1.10.2")}
	hostid=${opt_hostid:-$(head -c4 /dev/urandom | od -A none -t x4 | xargs)}

	echo
	blue "Scaffold: ${host}  system=${target_system}  layout=${disk_layout}  ip=${ip4}  gw=${gw4}  dns=${dns}  hostId=${hostid}"
	confirm "Create host config?" || {
		yellow "Aborted."
		exit 0
	}

	if [ "$dry_run" -eq 1 ]; then
		yellow "[DRY-RUN] would scaffold ${host_dir}/default.nix (${target_system}), ${home_file}, network.nix entry"
		return 0
	fi

	mkdir -p "$host_dir"
	sed \
		-e "s/hostName = \"foo\"/hostName = \"${host}\"/" \
		-e "s/hostId = \"xxxxx\"/hostId = \"${hostid}\"/" \
		-e "s/layout = \"ext4\"/layout = \"${disk_layout}\"/" \
		-e "s/hostPlatform = lib.mkDefault \"x86_64-linux\"/hostPlatform = lib.mkDefault \"${target_system}\"/" \
		-e '/# \!\!\!\[FIXME\]\!\!\!/d' \
		"$host_template" >"${host_dir}/default.nix"
	green "Created hosts/nixos/${host}/default.nix"

	cp "$home_template" "$home_file"
	green "Created home/channinghe/${host}.nix"

	if [ ! -f "$network_nix" ]; then
		red "network.nix missing: ${network_nix} — add the entry manually."
	elif grep -qE "^[[:space:]]*${host} = \{" "$network_nix"; then
		yellow "network.nix already has ${host}, skipping."
	else
		local tmp
		tmp=$(mktemp)
		NH_H="$host" NH_IP="$ip4" NH_GW="$gw4" NH_DNS="$dns" awk '/# Other hosts/ {
			printf "      %s = {\n", ENVIRON["NH_H"]
			printf "        ip4 = \"%s\";\n", ENVIRON["NH_IP"]
			printf "        gateway4 = \"%s\";\n", ENVIRON["NH_GW"]
			printf "        dns = [ \"%s\" ];\n", ENVIRON["NH_DNS"]
			printf "      };\n"
		} { print }' "$network_nix" >"$tmp"
		mv "$tmp" "$network_nix"
		green "Added network.nix entry for ${host}"
	fi

	# Nix flakes only see git-tracked files; stage the new host so later steps
	# (install builds .#${host}) can evaluate it.
	git -C "$git_root" add "hosts/nixos/${host}" "$home_file" 2>/dev/null || true
	REPO_SCAFFOLDED=1
}

###############################################################################
# Step: secrets  (ssh host key -> sops)
###############################################################################

function step_secrets() {
	if [ "$REPO_SECRETS" -eq 1 ]; then
		yellow "secrets: ssh host key already in sops — skipping."
		return 0
	fi
	local secret_file="${nix_secrets_dir}/secrets/${host}.yaml"
	local config="${nix_secrets_dir}/.sops.yaml"
	export SOPS_FILE="$config"

	if [ "$dry_run" -eq 1 ]; then
		yellow "[DRY-RUN] would generate ssh host key + write to ${secret_file}"
		return 0
	fi

	local tmp
	tmp=$(mktemp -d -p "$spawn_tmp")

	ssh-keygen -t ed25519 -f "${tmp}/key" -C "${target_user}@${host}" -N "" -q
	local age_key
	age_key=$(ssh-to-age -i "${tmp}/key.pub")
	[[ $age_key == age1* ]] || {
		red "Bad age key: $age_key"
		exit 1
	}
	green "Host age key: ${age_key}"

	sops_update_age_key "hosts" "$host" "$age_key"
	sops_add_creation_rules "$target_user" "$host"

	if [ ! -f "$secret_file" ]; then
		mkdir -p "$(dirname "$secret_file")"
		{
			echo "keys:"
			echo "  ssh_host_ed25519_key: |"
			sed 's/^/    /' "${tmp}/key"
			echo "  ssh_host_ed25519_key_pub: \"$(cat "${tmp}/key.pub")\""
		} >"${tmp}/plain.yaml"
		sops --config "$config" --input-type yaml --output-type yaml \
			--filename-override "secrets/${host}.yaml" -e "${tmp}/plain.yaml" >"$secret_file"
	else
		sops --config "$config" --set '["keys"]["ssh_host_ed25519_key"] '"$(jq -Rs . <"${tmp}/key")" "$secret_file"
		sops --config "$config" --set '["keys"]["ssh_host_ed25519_key_pub"] '"$(jq -Rs . <"${tmp}/key.pub")" "$secret_file"
	fi
	green "Wrote ssh host key to ${secret_file}"

	# Copy user password from shared.yaml so the user can log in post-install.
	local shared="${nix_secrets_dir}/secrets/shared.yaml"
	if [ -f "$shared" ] && sops --config "$config" -d --extract '["passwords"]["'"$target_user"'"]' "$shared" >/dev/null 2>&1; then
		local pw
		pw=$(sops --config "$config" -d --extract '["passwords"]["'"$target_user"'"]' "$shared" | jq -Rs .)
		sops --config "$config" --set '["passwords"]["'"$target_user"'"] '"$pw" "$secret_file"
		green "Copied passwords/${target_user} into secrets/${host}.yaml"
	else
		yellow "WARNING: passwords/${target_user} not in shared.yaml — set a password before install."
	fi

	rm -f "${tmp}/key" "${tmp}/key.pub"

	green "Rekeying secrets/*.yaml against updated .sops.yaml"
	local sf_rel rekey_failed=0
	shopt -s nullglob
	for sf_rel in "${nix_secrets_dir}"/secrets/*.yaml; do
		sf_rel="${sf_rel#"${nix_secrets_dir}"/}"
		if ! (cd "$nix_secrets_dir" && sops --config "$config" updatekeys -y "$sf_rel"); then
			red "sops updatekeys failed for ${sf_rel}"
			rekey_failed=1
		fi
	done
	shopt -u nullglob
	[ "$rekey_failed" -eq 0 ] || {
		red "Rekey failed — fix .sops.yaml / secrets before continuing."
		exit 1
	}
	green "Rekey complete; shared.yaml now readable by ${host}."
	yellow "NOTE: commit + push nix-secrets, then update the flake input (nix flake update nix-secrets)."
	REPO_SECRETS=1
}

###############################################################################
# Step: disk  (discover device + NIC MAC, back-fill config)
###############################################################################

function host_file() { echo "${git_root}/hosts/nixos/${host}/default.nix"; }

# Layout from the host's bootDiskLayout call ("" if not scaffolded).
function host_layout() {
	[ -f "$(host_file)" ] || return 0
	sed -nE 's/^[[:space:]]*layout[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$(host_file)" | head -n1
}

# disk_pinned <attr> — is `<attr> = "/dev/...";` set? (anchored to ^ so it's a
# real attribute line, not a comment; `disk` never matches `disk2`).
function disk_pinned() {
	grep -qE "^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"/dev/" "$(host_file)"
}

function pinned_disk() {
	sed -nE "s#^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"(/dev/[^\"]+)\".*#\\1#p" "$(host_file)" | head -n1
}

# stable_disk_alias <kernel name> — most stable alias on the target:
# by-id > by-path > raw. Warnings go to stderr so callers can capture stdout.
function stable_disk_alias() {
	local raw=$1 alias
	# shopt -s nullglob so an empty /dev/disk/by-id/ doesn't fall through as a
	# literal '*' path (silent fallback to /dev/${raw} was the previous bug).
	# Skip -part* symlinks explicitly; they point at partitions, not the disk.
	alias=$(tssh "
		shopt -s nullglob
		for dir in /dev/disk/by-id /dev/disk/by-path; do
			for d in \"\$dir\"/*; do
				case \"\$d\" in *-part*) continue ;; esac
				[ \"\$(readlink -f \"\$d\")\" = \"/dev/${raw}\" ] && { echo \"\$d\"; exit 0; }
			done
		done
		echo \"/dev/${raw}\"
	")
	case "$alias" in
	/dev/disk/by-id/*) : ;;
	/dev/disk/by-path/*)
		yellow "No /dev/disk/by-id/ alias for /dev/${raw}; using by-path. Stable per PCIe slot but changes if you move the drive." >&2
		;;
	*)
		yellow "No stable /dev/disk/{by-id,by-path} alias for /dev/${raw}; falling back to the kernel name." >&2
		yellow "This name (nvmeXnY / sdX) can shuffle across reboots — check the target's /dev/disk/by-id/ before continuing." >&2
		;;
	esac
	echo "$alias"
}

function step_disk() {
	if [ "$REPO_DISK_SET" -eq 1 ]; then
		yellow "disk: already pinned — skipping."
		return 0
	fi
	if [ -z "$target_ip" ] || [ "$TARGET_STATE" = "UNREACHABLE" ]; then
		red "disk: target ${target_ip:-?} unreachable; -d <ip> required."
		exit 1
	fi

	green "Probing target disks on ${target_ip}..."
	tssh "lsblk -dno NAME,SIZE,MODEL,TYPE | grep disk" || true
	local -a raws=()
	mapfile -t raws < <(tssh "lsblk -dno NAME,TYPE | awk '\$2==\"disk\"{print \$1}'")
	[ ${#raws[@]} -gt 0 ] || {
		red "No disk found on target."
		exit 1
	}

	local chosen="" chosen2=""
	if disk_pinned disk; then
		chosen=$(pinned_disk disk)
		green "Primary disk already pinned: ${chosen}"
	else
		chosen=$(ask "Primary disk device (Enter to accept)" "$(stable_disk_alias "${raws[0]}")")
		green "Using primary disk: ${chosen}"
	fi

	if [ "$(host_layout)" = "zfs-mirror" ] && ! disk_pinned disk2; then
		local primary_dev r default2=""
		primary_dev=$(tssh "readlink -f '${chosen}'")
		for r in "${raws[@]}"; do
			if [ "/dev/${r}" != "$primary_dev" ]; then
				default2=$(stable_disk_alias "$r")
				break
			fi
		done
		chosen2=$(ask "Secondary (mirror) disk device" "$default2")
		[ -n "$chosen2" ] || {
			red "zfs-mirror needs a second disk."
			exit 1
		}
		[ "$(tssh "readlink -f '${chosen2}'")" != "$primary_dev" ] || {
			red "Secondary disk resolves to the primary (${primary_dev})."
			exit 1
		}
		green "Using secondary disk: ${chosen2}"
	fi

	# Discover the NIC MAC for reliable systemd-networkd matching.
	local iface mac
	iface=$(tssh "ip -o -4 route show default | awk '{print \$5; exit}'")
	mac=$(tssh "cat /sys/class/net/${iface}/address" 2>/dev/null || true)
	green "Primary NIC ${iface} MAC: ${mac:-unknown}"

	if [ "$dry_run" -eq 1 ]; then
		yellow "[DRY-RUN] would pin disk=${chosen}${chosen2:+, disk2=${chosen2}}, mac=${mac} (iface ${iface})"
		return 0
	fi

	disk_pinned disk || backfill_disk_attr disk "$chosen" layout
	if [ -n "$chosen2" ]; then backfill_disk_attr disk2 "$chosen2" disk; fi
	if [ -n "$mac" ]; then backfill_network_mac "$mac" "$iface"; fi
	REPO_DISK_SET=1
}

# backfill_disk_attr <attr> <dev> <anchor> — set `<attr> = "<dev>";` inside the
# host's lib.custom.bootDiskLayout call, inserted on its own line right after
# the `<anchor> = "...";` line (disk after layout, disk2 after disk).
function backfill_disk_attr() {
	local attr="$1" dev="$2" anchor="$3" f
	f=$(host_file)
	if grep -qE "^[[:space:]]*${attr}[[:space:]]*=" "$f"; then
		# Device paths never contain '#', so it's safe as the sed delimiter.
		sed -i.bak -E "s#^([[:space:]]*)${attr}[[:space:]]*=[[:space:]]*\"[^\"]*\";#\\1${attr} = \"${dev}\";#" "$f"
		rm -f "${f}.bak"
	else
		# awk instead of a sed `\n` replacement, which BSD sed doesn't support.
		# Reuses the anchor line's indentation and keeps its trailing comment.
		local tmp
		tmp=$(mktemp)
		awk -v attr="$attr" -v dev="$dev" -v anchor="$anchor" '
			{ print }
			!done && $0 ~ ("^[[:space:]]*" anchor "[[:space:]]*=") {
				indent = $0
				sub(/[^[:space:]].*$/, "", indent)
				printf "%s%s = \"%s\";\n", indent, attr, dev
				done = 1
			}
		' "$f" >"$tmp"
		# cat, not mv: keep the tracked file's mode instead of mktemp's 0600.
		cat "$tmp" >"$f"
		rm -f "$tmp"
	fi
	green "Pinned ${attr} = \"${dev}\" in hosts/nixos/${host}/default.nix"
}

# Add `mac = "<mac>"; interface = "<iface>";` to the host's network.nix entry.
function backfill_network_mac() {
	local mac="$1" iface="$2"
	[ -f "$network_nix" ] || return 0
	grep -q "mac = \"${mac}\"" "$network_nix" && return 0
	local tmp
	tmp=$(mktemp)
	NH_H="$host" NH_MAC="$mac" NH_IF="$iface" awk '
		$0 ~ ("^[[:space:]]*" ENVIRON["NH_H"] " = \\{") { inblk=1 }
		inblk && /dns = / {
			print
			printf "        mac = \"%s\";\n", ENVIRON["NH_MAC"]
			printf "        interface = \"%s\";\n", ENVIRON["NH_IF"]
			inblk=0
			next
		}
		{ print }
	' "$network_nix" >"$tmp"
	mv "$tmp" "$network_nix"
	green "Back-filled mac/interface for ${host} in network.nix"
}

###############################################################################
# Gate: nix-secrets must be pushed + locked before building .#<host>
###############################################################################

# The flake consumes nix-secrets as a LOCKED remote input, so local edits to
# network.nix / sops (from scaffold + secrets) are invisible until pushed and
# the lock is bumped. You push (git is yours); spawn then updates the input.
function nix_secrets_gate() {
	[ -d "${nix_secrets_dir}/.git" ] || return 0
	git -C "$nix_secrets_dir" diff --quiet && git -C "$nix_secrets_dir" diff --cached --quiet && return 0

	echo
	yellow "nix-secrets has uncommitted changes — the flake won't see them until pushed:"
	git -C "$nix_secrets_dir" status --short
	echo
	yellow "Commit & push nix-secrets, then spawn will update the flake input:"
	echo "  cd ${nix_secrets_dir} && git add -A && git commit -m 'add ${host}' && git push"
	if [ "$dry_run" -eq 1 ]; then
		yellow "[DRY-RUN] would wait for push, then: nix flake update nix-secrets"
		return 0
	fi
	[ "$assume_yes" -eq 1 ] || read -r -p "$(printf '\x1B[34m[?] Press Enter once nix-secrets is pushed (Ctrl-C to abort): \x1B[0m')" _
	green "Updating nix-secrets flake input..."
	nix flake update nix-secrets
}

###############################################################################
# Step: install  (nixos-anywhere: disko + facter + install + reboot)
###############################################################################

# Anything but the live installer is a running OS that nixos-anywhere kexecs
# out of and wipes. The plan-level confirm is skipped by -y, so this one isn't.
function confirm_wipe() {
	[ "$TARGET_STATE" = "INSTALLER" ] && return 0
	red "install: ${target_ip} is ${TARGET_STATE}, not the NixOS installer — its disks will be WIPED."
	if [ "$assume_yes" -eq 1 ]; then
		[ "$force_wipe" -eq 1 ] && return 0
		red "Refusing under -y without --force-wipe."
		exit 1
	fi
	local typed
	typed=$(ask "Type the host name '${host}' to wipe ${target_ip}")
	[ "$typed" = "$host" ] || {
		red "Name mismatch — aborted."
		exit 1
	}
}

function step_install() {
	if [ "$TARGET_STATE" = "INSTALLED_THIS" ]; then
		yellow "install: target already running ${host} — skipping."
		return 0
	fi
	[ -n "$target_ip" ] || {
		red "install: -d <ip> required."
		exit 1
	}
	[ "$REPO_SECRETS" -eq 1 ] || {
		red "install: secrets not ready (run secrets step first)."
		exit 1
	}
	confirm_wipe

	# Extract the sops ssh host key into a secure temp for --extra-files.
	local tmp persist="etc/ssh"
	tmp=$(mktemp -d -p "$spawn_tmp")
	install -d -m755 "${tmp}/${persist}"
	local sf="${nix_secrets_dir}/secrets/${host}.yaml" sc="${nix_secrets_dir}/.sops.yaml"
	sops --config "$sc" -d --extract '["keys"]["ssh_host_ed25519_key"]' "$sf" >"${tmp}/${persist}/ssh_host_ed25519_key"
	sops --config "$sc" -d --extract '["keys"]["ssh_host_ed25519_key_pub"]' "$sf" >"${tmp}/${persist}/ssh_host_ed25519_key.pub"
	chmod 600 "${tmp}/${persist}/ssh_host_ed25519_key"

	# Installer target → skip kexec; anything else → let nixos-anywhere kexec.
	local -a phases=()
	[ "$TARGET_STATE" = "INSTALLER" ] && phases=(--phases "disko,install,reboot")

	# Build strategy (see --build-strategy). nixos-anywhere forwards --option /
	# --build-on to its own nix build, so no local pre-build is needed.
	local -a build_args=()
	case "$build_strategy" in
	on-target) build_args=(--build-on remote) ;;
	no-remote) build_args=(--build-on local --option builders "") ;;
	no-external) build_args=(--build-on local --option external-builders "[]") ;;
	esac

	green "Running nixos-anywhere on ${host} @ ${target_ip} (${TARGET_STATE}, build: ${build_strategy})"
	if [ "$dry_run" -eq 1 ]; then
		yellow "[DRY-RUN] nixos-anywhere --flake ${git_root}#${host} --generate-hardware-config nixos-facter hosts/nixos/${host}/facter.json ${build_args[*]} ${phases[*]} root@${target_ip}"
		return 0
	fi

	SHELL=/bin/sh nix run github:nix-community/nixos-anywhere -- \
		--flake "${git_root}#${host}" \
		--generate-hardware-config nixos-facter "${git_root}/hosts/nixos/${host}/facter.json" \
		--extra-files "$tmp" \
		--ssh-port "$ssh_port" \
		"${build_args[@]}" \
		"${phases[@]}" \
		--target-host "root@${target_ip}"

	# facter.json must be git-tracked for the flake to see it.
	git -C "$git_root" add "hosts/nixos/${host}/facter.json" "hosts/nixos/${host}/" 2>/dev/null || true
	green "Generated + staged hosts/nixos/${host}/facter.json"

	# install used the full config, so the booted system is already complete —
	# just confirm it comes back up.
	wait_for_target_boot
}

function wait_for_target_boot() {
	yellow "Waiting for ${host} to reboot into the installed system..."
	# nixos-anywhere already waited for the reboot to start, so probe the current
	# IP straight away. Only ask for a new IP if it stays unreachable (e.g. DHCP
	# handed out a different lease). No upfront prompt for the common stable-IP case.
	local rounds=0 _
	while true; do
		for _ in $(seq 1 40); do
			tssh "command -v nixos-version" >/dev/null && {
				green "Target reachable at ${target_ip}."
				return 0
			}
			sleep 3
		done
		rounds=$((rounds + 1))
		yellow "${host} still unreachable at ${target_ip} after $((rounds * 2)) min."
		[ "$assume_yes" -eq 1 ] && {
			yellow "Giving up the wait; verify ${host} manually."
			return 0
		}
		local ip
		ip=$(ask "Target IP (Enter to keep ${target_ip}, Ctrl-C to abort)" "$target_ip")
		[ -n "$ip" ] && target_ip="$ip"
	done
}

###############################################################################
# Main
###############################################################################

green "=========================================="
green "spawn: ${host}"
green "=========================================="
[ "$dry_run" -eq 1 ] && yellow "DRY-RUN: no changes will be made."

detect_repo_state
detect_target_state
build_plan
print_state_and_plan

[ "$dry_run" -eq 1 ] && exit 0
confirm "Proceed with this plan?" || {
	yellow "Aborted."
	exit 0
}

step_enabled scaffold && step_scaffold
step_enabled secrets && step_secrets
step_enabled disk && step_disk
# Building .#<host> for install needs the pushed+locked nix-secrets.
step_enabled install && nix_secrets_gate
step_enabled install && step_install

green "=========================================="
green "spawn complete for ${host}"
green "=========================================="
