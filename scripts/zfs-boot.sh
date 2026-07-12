#!/usr/bin/env bash
set -euo pipefail

# zfs-boot — manage the mirror side of a ZFS boot pool.
#
# Two modes:
#   attach   convert a single-disk pool into a 2-way mirror by adding a new disk
#   replace  swap a failed/degraded mirror member for a new disk
#
# Idempotent & resumable: every phase probes the real system (GPT layout,
# PARTLABELs, vfat filesystem, pool topology, resilver progress) and skips
# itself if the desired state is already reached. Interruption at any point is
# recoverable by re-running the same command.
#
# Constraints:
#   * disk arguments MUST be /dev/disk/by-id/* — kernel names (/dev/sdX,
#     /dev/nvme*n1) renumber across boots and are rejected.
#   * runs on the TARGET host (needs zpool, zfs, sgdisk, mkfs.vfat, partprobe,
#     udevadm, findmnt, blkid, lsblk, blockdev, awk).
#   * NEVER writes the bootloader — that's `nixos-rebuild boot`'s job after you
#     update nix-config. This script only touches disks and the ZFS pool.
#
# See also: hosts/common/optional/system/zfs-boot.nix (mirroredBoots logic),
# lib/boot-disk.nix (layout dispatch), hosts/common/disks/zfs-mirror-disk.nix
# (disko schema).

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

###############################################################################
# Dependency check
###############################################################################

REQUIRED_TOOLS=(zpool zfs sgdisk partprobe mkfs.vfat udevadm findmnt blkid lsblk blockdev awk grep sed readlink)
function check_dependencies() {
	local missing=()
	for cmd in "${REQUIRED_TOOLS[@]}"; do
		command -v "$cmd" &>/dev/null || missing+=("$cmd")
	done
	if [ ${#missing[@]} -gt 0 ]; then
		red "ERROR: Missing required tools: ${missing[*]}"
		exit 1
	fi
}

###############################################################################
# Defaults & globals
###############################################################################

mode=""
pool="rpool"
existing_disk=""
new_disk=""
failed_ref=""
esp_part=1
pool_part=2
boot_mount="/boot2"
esp_partlabel=""
pool_partlabel=""
gpt_backup_dir="/root/zfs-boot-gpt-backups"
resilver_poll=30 # seconds between resilver status prints
only_step=""
from_step=""
declare -a skip_steps=()
assume_yes=0
dry_run=0

###############################################################################
# Usage
###############################################################################

function help_and_exit() {
	cat <<EOF

zfs-boot — extend or heal a ZFS mirror-boot pool. Idempotent, resumable.

USAGE:
  $0 attach  --new <by-id> [--existing <by-id>] [OPTIONS]
  $0 replace --failed <ref> --new <by-id>       [OPTIONS]

MODES:
  attach     Convert single-disk pool -> 2-way mirror. Copies GPT from the
             existing member, relabels the new disk, makes vfat on the new
             ESP, and issues 'zpool attach'.
  replace    Swap a failed/degraded mirror member. Copies GPT from the
             surviving member, matches the failed disk's PARTLABELs, and
             issues 'zpool replace'.

REQUIRED (attach):
  --new <by-id>              /dev/disk/by-id/... of the new disk

REQUIRED (replace):
  --failed <ref>             failed member as shown in 'zpool status' — a full
                             /dev/... path, a GUID, or a bare device name
  --new <by-id>              /dev/disk/by-id/... of the replacement disk

COMMON OPTIONS:
  --pool <name>              zpool name (default: rpool)
  --existing <by-id>         existing pool member (attach mode). Auto-detected
                             from 'zpool status' if omitted.
  --esp-part <N>             ESP partition number on both disks (default: 1)
  --pool-part <N>            ZFS partition number on both disks (default: 2)
  --boot-mount <path>        mountpoint for the new ESP (default: /boot2)
  --esp-partlabel <str>      PARTLABEL for the new ESP. Defaults:
                               attach  -> 'disk-disk2-EFI'
                               replace -> the failed disk's label
  --pool-partlabel <str>     PARTLABEL for the new ZFS partition. Defaults:
                               attach  -> 'disk-disk2-rpool'
                               replace -> the failed disk's label
  --gpt-backup-dir <path>    where GPT backups are written (default: ${gpt_backup_dir})

STEP CONTROL:
  --only <step>              run just this step
  --from <step>              run from this step to the end
  --skip <step>              skip a step (repeatable)

  attach steps:  backup-gpt partition-new relabel-new mkfs-esp mount-boot
                 zpool-attach wait-resilver hint-nix-config
  replace steps: backup-gpt partition-new relabel-new mkfs-esp mount-boot
                 zpool-replace wait-resilver hint-nix-config

OTHER:
  -y, --yes                  don't ask for confirmation
  --dry-run                  print plan and would-run commands, change nothing
  --debug                    set -x
  -h, --help

EXAMPLES:
  # zfs single -> mirror, new disk is a fresh NVMe
  $0 attach --new /dev/disk/by-id/nvme-SKHynix_HFS256GEM9X169N_5ID2Q001

  # existing disk explicit (skip auto-detect)
  $0 attach \\
    --existing /dev/disk/by-id/nvme-Old_SN123 \\
    --new      /dev/disk/by-id/nvme-New_SN456

  # replace a failed mirror member
  $0 replace \\
    --failed /dev/disk/by-partlabel/disk-disk1-rpool \\
    --new    /dev/disk/by-id/nvme-Replacement_SN789

  # dry-run first
  $0 attach --new /dev/disk/by-id/nvme-New --dry-run

EOF
	exit "${1:-0}"
}

###############################################################################
# Argument parsing
###############################################################################

[ $# -eq 0 ] && help_and_exit 0
case "${1:-}" in
attach | replace)
	mode=$1
	shift
	;;
-h | --help) help_and_exit 0 ;;
*)
	red "ERROR: first argument must be 'attach' or 'replace' (got '$1')"
	help_and_exit 1
	;;
esac

while [[ $# -gt 0 ]]; do
	case "$1" in
	-h | --help) help_and_exit 0 ;;
	--pool)
		pool=$2
		shift 2
		;;
	--existing)
		existing_disk=$2
		shift 2
		;;
	--new)
		new_disk=$2
		shift 2
		;;
	--failed)
		failed_ref=$2
		shift 2
		;;
	--esp-part)
		esp_part=$2
		shift 2
		;;
	--pool-part)
		pool_part=$2
		shift 2
		;;
	--boot-mount)
		boot_mount=$2
		shift 2
		;;
	--esp-partlabel)
		esp_partlabel=$2
		shift 2
		;;
	--pool-partlabel)
		pool_partlabel=$2
		shift 2
		;;
	--gpt-backup-dir)
		gpt_backup_dir=$2
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
		red "Unexpected positional argument: $1"
		help_and_exit 1
		;;
	esac
done

###############################################################################
# Argument validation
###############################################################################

function die() {
	red "$*"
	exit 1
}

function require_by_id() {
	local label=$1 val=$2
	[ -n "$val" ] || die "ERROR: --$label is required"
	[[ $val == /dev/disk/by-id/* ]] || die "ERROR: --$label must be /dev/disk/by-id/* (got '$val')"
	[ -b "$val" ] || die "ERROR: --$label points to '$val' but it's not a block device"
}

[ "$(id -u)" -eq 0 ] || die "ERROR: must run as root"
check_dependencies

require_by_id "new" "$new_disk"
if [ -n "$existing_disk" ]; then
	require_by_id "existing" "$existing_disk"
fi

case "$mode" in
attach)
	[ -n "$failed_ref" ] && die "ERROR: --failed is meaningless in attach mode"
	;;
replace)
	[ -n "$failed_ref" ] || die "ERROR: --failed is required in replace mode"
	;;
esac

# Default labels.
if [ -z "$esp_partlabel" ]; then
	[ "$mode" = "attach" ] && esp_partlabel="disk-disk2-EFI"
fi
if [ -z "$pool_partlabel" ]; then
	[ "$mode" = "attach" ] && pool_partlabel="disk-disk2-rpool"
fi

###############################################################################
# Small helpers
###############################################################################

# run <cmd string> — dispatches to dry-run print or actual eval. Callers pass a
# single already-quoted string (e.g. `run "sgdisk '$disk' --backup=..."`),
# so we eval "$*" (shellcheck's "eval as string" form) rather than "$@".
function run() {
	if [ "$dry_run" -eq 1 ]; then
		yellow "  [dry-run] $*"
	else
		blue "  \$ $*"
		eval "$*"
	fi
}

function confirm() {
	[ "$assume_yes" -eq 1 ] && return 0
	yes_or_no "$1"
}

function partition_path() {
	# by-id + partition number -> stable by-id partition path
	echo "$1-part$2"
}

# Resolve a by-id or partlabel/partuuid to /dev/nvmeXnY / /dev/sdX (never for
# writing — only for use with commands that need the kernel name, e.g. blockdev,
# sgdisk, mkfs, partprobe).
function resolve_dev() {
	readlink -f "$1"
}

# Get 64-bit device size in bytes.
function dev_size_bytes() {
	blockdev --getsize64 "$(resolve_dev "$1")"
}

# Test if a block device (partition or whole disk) is actively in use.
function dev_in_use() {
	local d=$1
	local resolved
	resolved=$(resolve_dev "$d")
	# Mounted?
	if findmnt --source "$resolved" >/dev/null 2>&1; then
		return 0
	fi
	# In any zpool? zpool status shows the base name, so match by basename.
	local base
	base=$(basename "$resolved")
	if zpool status 2>/dev/null | grep -qwF "$base"; then
		return 0
	fi
	# Held by md / LVM / LUKS / bcache / etc?
	local type
	type=$(lsblk -no TYPE "$resolved" 2>/dev/null | head -1 || true)
	case "$type" in
	raid* | lvm | crypt | dmraid | bcache) return 0 ;;
	esac
	return 1
}

# Reject if any partition of $1 is in use. Whole-disk overwrite is dangerous.
function assert_disk_free() {
	local disk=$1
	local resolved
	resolved=$(resolve_dev "$disk")
	# Every partition of $resolved
	local p
	while IFS= read -r p; do
		[ -z "$p" ] && continue
		[ "$p" = "$resolved" ] && continue
		if dev_in_use "$p"; then
			red "SAFETY: $p is in use (mounted / in zpool / md / lvm / luks)."
			red "SAFETY: Refusing to touch $disk. Detach it first."
			exit 1
		fi
	done < <(lsblk -lno PATH "$resolved" 2>/dev/null | tail -n +2)
}

###############################################################################
# Pool topology & existing-disk auto-detection
###############################################################################

function pool_topology() {
	# Prints 'single' or 'mirror' or 'other'. Only understands single-vdev pools.
	local top
	top=$(zpool list -H -o name,health "$pool" 2>/dev/null | awk '{print $1}')
	[ "$top" = "$pool" ] || die "ERROR: pool '$pool' not found"
	# Count vdev config lines: mirror-N line indicates mirror
	if zpool status "$pool" 2>/dev/null | grep -qE '^\s+mirror-[0-9]+'; then
		echo "mirror"
	else
		echo "single"
	fi
}

function pool_healthy() {
	zpool status -x "$pool" 2>&1 | grep -qE "pool '${pool}' is healthy|all pools are healthy"
}

# For attach: find the single existing member's disk path (by-id if resolvable).
function detect_existing_disk() {
	# zpool status shows the leaf vdev — could be a partlabel path, by-id path,
	# or a bare device name. Extract the first leaf under the pool config.
	local leaf resolved by_id
	leaf=$(zpool status -P "$pool" 2>/dev/null |
		awk -v p="$pool" '
			$0 ~ "^\t" p "$" { in_pool=1; next }
			in_pool && NF>=2 && $1 ~ /^\// { print $1; exit }
		')
	[ -n "$leaf" ] || die "ERROR: could not detect existing pool member (use --existing)"
	resolved=$(resolve_dev "$leaf")
	# Walk back to a stable by-id link that points to the parent disk.
	local parent
	parent=$(lsblk -no PKNAME "$resolved" 2>/dev/null | head -1)
	[ -n "$parent" ] || die "ERROR: cannot find parent disk of $resolved"
	# Find a /dev/disk/by-id/* that resolves to /dev/$parent AND does not end in -partN
	by_id=$(find /dev/disk/by-id -maxdepth 1 -type l 2>/dev/null | while read -r link; do
		tgt=$(readlink -f "$link")
		if [ "$tgt" = "/dev/$parent" ] && [[ ! $link =~ -part[0-9]+$ ]]; then
			echo "$link"
			break
		fi
	done)
	[ -n "$by_id" ] || die "ERROR: no /dev/disk/by-id/ symlink for /dev/$parent"
	echo "$by_id"
}

# For replace: parse zpool status for the failed leaf under the mirror.
function find_failed_leaf() {
	# We just echo back what the user gave us; zpool replace accepts a wide
	# variety of identifiers (path, guid, partlabel). Sanity-check it exists
	# in the pool though.
	if ! zpool status "$pool" 2>/dev/null | grep -qwF "$(basename "$failed_ref")"; then
		red "WARNING: '$failed_ref' (basename '$(basename "$failed_ref")') not visibly present in zpool status."
		red "         zpool replace may still accept it (guid resolution). Continue?"
		confirm "Proceed anyway?" || exit 1
	fi
	echo "$failed_ref"
}

###############################################################################
# Phase implementations — each has _check (returns 0 if already done) and _run.
###############################################################################

# ---- backup-gpt ---------------------------------------------------------------

function phase_backup_gpt_check() {
	# Skip if backups for both source and target disks already exist and are
	# newer than the disk's mtime (proxy — sgdisk backups have no mtime marker).
	local src=$1 tgt=$2
	local src_bak tgt_bak
	src_bak="${gpt_backup_dir}/$(basename "$(resolve_dev "$src")").gpt.bak"
	tgt_bak="${gpt_backup_dir}/$(basename "$(resolve_dev "$tgt")").gpt.bak"
	[ -s "$src_bak" ] && [ -s "$tgt_bak" ]
}

function phase_backup_gpt_run() {
	local src=$1 tgt=$2
	run "mkdir -p '$gpt_backup_dir'"
	local src_resolved tgt_resolved
	src_resolved=$(resolve_dev "$src")
	tgt_resolved=$(resolve_dev "$tgt")
	run "sgdisk '$src_resolved' --backup='${gpt_backup_dir}/$(basename "$src_resolved").gpt.bak'"
	# Target may be blank — sgdisk still writes a backup with the (possibly empty) GPT.
	run "sgdisk '$tgt_resolved' --backup='${gpt_backup_dir}/$(basename "$tgt_resolved").gpt.bak' || true"
	green "GPT backups saved to $gpt_backup_dir"
}

# ---- partition-new -----------------------------------------------------------

function phase_partition_new_check() {
	# Both ESP and pool partitions exist on the new disk with sensible types.
	local esp pool_part_path
	esp=$(partition_path "$new_disk" "$esp_part")
	pool_part_path=$(partition_path "$new_disk" "$pool_part")
	[ -b "$esp" ] && [ -b "$pool_part_path" ] || return 1
	# Sizes plausible? At minimum, both partitions exist.
	return 0
}

function phase_partition_new_run() {
	local src=$1 tgt=$2
	# Safety: don't overwrite a disk that has active partitions.
	assert_disk_free "$tgt"
	# Size check.
	local src_bytes tgt_bytes
	src_bytes=$(dev_size_bytes "$src")
	tgt_bytes=$(dev_size_bytes "$tgt")
	if [ "$tgt_bytes" -lt "$src_bytes" ]; then
		die "ERROR: new disk ($tgt, ${tgt_bytes}B) smaller than existing ($src, ${src_bytes}B)"
	fi
	local src_resolved tgt_resolved
	src_resolved=$(resolve_dev "$src")
	tgt_resolved=$(resolve_dev "$tgt")
	run "sgdisk '$src_resolved' --replicate='$tgt_resolved'"
	run "sgdisk -G '$tgt_resolved'"
	run "partprobe '$tgt_resolved'"
	run "udevadm settle"
}

# ---- relabel-new -------------------------------------------------------------

function phase_relabel_new_check() {
	local esp_pt pool_pt cur_esp cur_pool
	esp_pt=$(partition_path "$new_disk" "$esp_part")
	pool_pt=$(partition_path "$new_disk" "$pool_part")
	[ -b "$esp_pt" ] && [ -b "$pool_pt" ] || return 1
	cur_esp=$(blkid -o value -s PARTLABEL "$esp_pt" 2>/dev/null || true)
	cur_pool=$(blkid -o value -s PARTLABEL "$pool_pt" 2>/dev/null || true)
	# ESP check
	if [ -n "$esp_partlabel" ] && [ "$cur_esp" != "$esp_partlabel" ]; then return 1; fi
	# Pool partition check
	if [ -n "$pool_partlabel" ] && [ "$cur_pool" != "$pool_partlabel" ]; then return 1; fi
	return 0
}

function phase_relabel_new_run() {
	local tgt=$1 tgt_resolved
	tgt_resolved=$(resolve_dev "$tgt")
	if [ -n "$esp_partlabel" ]; then
		run "sgdisk -c $esp_part:'$esp_partlabel' '$tgt_resolved'"
	fi
	if [ -n "$pool_partlabel" ]; then
		run "sgdisk -c $pool_part:'$pool_partlabel' '$tgt_resolved'"
	fi
	run "partprobe '$tgt_resolved'"
	run "udevadm settle"
}

# ---- mkfs-esp ----------------------------------------------------------------

function phase_mkfs_esp_check() {
	local esp_pt
	esp_pt=$(partition_path "$new_disk" "$esp_part")
	[ -b "$esp_pt" ] || return 1
	[ "$(blkid -o value -s TYPE "$esp_pt" 2>/dev/null || true)" = "vfat" ]
}

function phase_mkfs_esp_run() {
	local esp_pt
	esp_pt=$(partition_path "$new_disk" "$esp_part")
	# Refuse if it's mounted — should never happen unless the user set up
	# something weird before running us.
	if findmnt --source "$esp_pt" >/dev/null 2>&1; then
		die "ERROR: $esp_pt is mounted; unmount before running mkfs.vfat"
	fi
	run "mkfs.vfat -F32 -n BOOT '$esp_pt'"
	run "udevadm settle"
}

# ---- mount-boot --------------------------------------------------------------

function phase_mount_boot_check() {
	local esp_pt actual
	esp_pt=$(partition_path "$new_disk" "$esp_part")
	actual=$(findmnt -no SOURCE "$boot_mount" 2>/dev/null || true)
	[ -n "$actual" ] && [ "$(resolve_dev "$actual")" = "$(resolve_dev "$esp_pt")" ]
}

function phase_mount_boot_run() {
	local esp_pt
	esp_pt=$(partition_path "$new_disk" "$esp_part")
	run "mkdir -p '$boot_mount'"
	# If something else is mounted here, refuse.
	if findmnt "$boot_mount" >/dev/null 2>&1; then
		local cur
		cur=$(findmnt -no SOURCE "$boot_mount")
		die "ERROR: $boot_mount is already mounted with $cur (expected $esp_pt)"
	fi
	run "mount '$esp_pt' '$boot_mount'"
}

# ---- zpool-attach (attach mode) ---------------------------------------------

function phase_zpool_attach_check() {
	# Pool topology is mirror AND the new pool partition is a leaf under it.
	[ "$(pool_topology)" = "mirror" ] || return 1
	local new_pool_pt basename
	new_pool_pt=$(partition_path "$new_disk" "$pool_part")
	[ -b "$new_pool_pt" ] || return 1
	basename=$(basename "$(resolve_dev "$new_pool_pt")")
	zpool status "$pool" 2>/dev/null | grep -qwF "$basename"
}

function phase_zpool_attach_run() {
	local existing_pt new_pt
	existing_pt=$(partition_path "$existing_disk" "$pool_part")
	new_pt=$(partition_path "$new_disk" "$pool_part")
	[ -b "$existing_pt" ] || die "ERROR: existing pool partition not found: $existing_pt"
	[ -b "$new_pt" ] || die "ERROR: new pool partition not found: $new_pt"
	run "zpool attach '$pool' '$existing_pt' '$new_pt'"
}

# ---- zpool-replace (replace mode) -------------------------------------------

function phase_zpool_replace_check() {
	# The new pool partition is a leaf under pool AND failed_ref no longer appears.
	local new_pool_pt basename
	new_pool_pt=$(partition_path "$new_disk" "$pool_part")
	[ -b "$new_pool_pt" ] || return 1
	basename=$(basename "$(resolve_dev "$new_pool_pt")")
	zpool status "$pool" 2>/dev/null | grep -qwF "$basename" || return 1
	# Failed device gone from status?
	if zpool status "$pool" 2>/dev/null | grep -qwF "$(basename "$failed_ref")"; then
		return 1
	fi
	return 0
}

function phase_zpool_replace_run() {
	local new_pt
	new_pt=$(partition_path "$new_disk" "$pool_part")
	[ -b "$new_pt" ] || die "ERROR: new pool partition not found: $new_pt"
	local failed
	failed=$(find_failed_leaf)
	run "zpool replace '$pool' '$failed' '$new_pt'"
}

# ---- wait-resilver -----------------------------------------------------------

function phase_wait_resilver_check() {
	# Pool healthy and no resilver in progress -> done.
	if pool_healthy && ! zpool status "$pool" 2>/dev/null | grep -qE 'resilver (in progress|repaired)'; then
		return 0
	fi
	# In-progress resilver -> not done.
	return 1
}

function phase_wait_resilver_run() {
	blue "Waiting for resilver on pool '$pool' — poll every ${resilver_poll}s. Ctrl+C to interrupt (safe, resumable)."
	if [ "$dry_run" -eq 1 ]; then
		yellow "  [dry-run] would poll 'zpool status $pool' until resilver clears"
		return 0
	fi
	while ! phase_wait_resilver_check; do
		local line
		line=$(zpool status "$pool" 2>/dev/null | grep -E 'scan:|resilver' | head -2 | tr '\n' ' ' || true)
		yellow "  [$(date +%H:%M:%S)] ${line:-checking...}"
		sleep "$resilver_poll"
	done
	green "Pool '$pool' is healthy, resilver complete."
}

# ---- hint-nix-config ---------------------------------------------------------

# Never marked "done" — this only prints guidance to stdout; running it twice
# is harmless.
function phase_hint_nix_config_check() { return 1; }

function phase_hint_nix_config_run() {
	local new_esp new_esp_uuid new_pool_pt
	new_esp=$(partition_path "$new_disk" "$esp_part")
	new_pool_pt=$(partition_path "$new_disk" "$pool_part")
	if [ "$dry_run" -eq 0 ]; then
		new_esp_uuid=$(blkid -o value -s UUID "$new_esp" 2>/dev/null || echo "<new-esp-uuid>")
	else
		new_esp_uuid="<new-esp-uuid>"
	fi

	green ""
	green "════════════ Update nix-config on your dev machine ════════════"
	cat <<EOF

Disk operations complete. Now update nix-config for this host so future
'nixos-rebuild boot' installs GRUB to /boot2 as well as /boot1.

Update the host's bootDiskLayout call:

  (lib.custom.bootDiskLayout inputs {
-   layout = "zfs";
+   layout = "zfs-mirror";
    disk  = "${existing_disk:-<existing by-id>}";
+   disk2 = "${new_disk}";
  })

The helper auto-sets hostSpec.zfsMirror via mkDefault -> zfs-boot.nix appends
the /boot2 mirroredBoots entry. Nothing else to do in nix.

Then on this host:
  sudo nixos-rebuild boot --flake <path>#<HOST>   # writes bootloader to both ESPs, does NOT activate
  sudo reboot                                     # verify boot from mirrored ESPs

After a successful reboot verify:
  zpool status ${pool}         # both members ONLINE
  findmnt /boot1 ${boot_mount} # both ESPs mounted

Optional acid test (later, when confident): power down, pull ${existing_disk:-old} \\
physically, boot — should come up on ${new_disk} alone (pool DEGRADED).

New disk paths for the record:
  ESP  partition: ${new_esp}       (UUID=${new_esp_uuid})
  ZFS  partition: ${new_pool_pt}
EOF
	green "═══════════════════════════════════════════════════════════════"
}

###############################################################################
# Plan build
###############################################################################

declare -a STEPS
case "$mode" in
attach) STEPS=(backup-gpt partition-new relabel-new mkfs-esp mount-boot zpool-attach wait-resilver hint-nix-config) ;;
replace) STEPS=(backup-gpt partition-new relabel-new mkfs-esp mount-boot zpool-replace wait-resilver hint-nix-config) ;;
esac

declare -A PLAN=()

function build_plan() {
	local s
	for s in "${STEPS[@]}"; do PLAN[$s]=1; done
	if [ -n "$only_step" ]; then
		for s in "${STEPS[@]}"; do PLAN[$s]=0; done
		PLAN[$only_step]=1
	fi
	if [ -n "$from_step" ]; then
		local seen=0
		for s in "${STEPS[@]}"; do
			[ "$s" = "$from_step" ] && seen=1
			PLAN[$s]=$seen
		done
	fi
	for s in "${skip_steps[@]}"; do PLAN[$s]=0; done
}

function step_enabled() { [ "${PLAN[$1]:-0}" -eq 1 ]; }

# Dispatch to phase impl. Source disk (for backup-gpt / partition-new) differs
# per mode; we resolve it here so phase impls stay simple.
function source_disk_for_copy() {
	# attach: copy from existing member. replace: copy from surviving member
	# (i.e. the one that isn't failed). Auto-detect if user gave --existing.
	if [ -n "$existing_disk" ]; then
		echo "$existing_disk"
		return
	fi
	detect_existing_disk
}

function run_phase() {
	local s=$1
	case "$s" in
	backup-gpt | partition-new)
		local src
		src=$(source_disk_for_copy)
		phase_"${s//-/_}"_run "$src" "$new_disk"
		;;
	relabel-new)
		phase_relabel_new_run "$new_disk"
		;;
	*)
		phase_"${s//-/_}"_run
		;;
	esac
}

function check_phase() {
	local s=$1
	case "$s" in
	backup-gpt)
		local src
		src=$(source_disk_for_copy)
		phase_backup_gpt_check "$src" "$new_disk"
		;;
	*)
		phase_"${s//-/_}"_check
		;;
	esac
}

###############################################################################
# Main
###############################################################################

function print_state() {
	blue "── Pool state ─────────────────────────────────────────────────"
	zpool list "$pool" 2>/dev/null || red "pool '$pool' not found"
	zpool status "$pool" 2>/dev/null || true
	blue "── Disks ──────────────────────────────────────────────────────"
	blue "existing: ${existing_disk:-<auto-detect>}"
	blue "new     : ${new_disk}"
	[ "$mode" = "replace" ] && blue "failed  : ${failed_ref}"
	blue "──────────────────────────────────────────────────────────────"
}

function print_plan() {
	blue "── Plan ($mode) ───────────────────────────────────────────────"
	local s label
	for s in "${STEPS[@]}"; do
		if ! step_enabled "$s"; then
			label="skip (filtered)"
		elif check_phase "$s" 2>/dev/null; then
			label="skip (already done)"
		else
			label="RUN"
		fi
		printf "  %-18s %s\n" "$s" "$label"
	done
	blue "──────────────────────────────────────────────────────────────"
}

# Pool sanity check before doing anything.
case "$mode" in
attach)
	top=$(pool_topology)
	if [ "$top" = "mirror" ]; then
		yellow "Pool '$pool' is already a mirror. Nothing to attach — did you mean 'replace'?"
		# Still allow --only to re-run individual phases (mkfs, mount, hint).
	elif [ "$top" != "single" ]; then
		die "ERROR: pool '$pool' has an unsupported topology (expected single or mirror)"
	fi
	# Fill in existing_disk from pool if omitted.
	if [ -z "$existing_disk" ]; then
		existing_disk=$(detect_existing_disk)
		green "Auto-detected --existing $existing_disk"
	fi
	;;
replace)
	top=$(pool_topology)
	[ "$top" = "mirror" ] || die "ERROR: pool '$pool' is not a mirror; use 'attach' first"
	;;
esac

build_plan
print_state
print_plan

if [ "$dry_run" -eq 1 ]; then
	green "Dry-run: nothing will be executed."
	exit 0
fi

confirm "Proceed with the plan above?" || {
	yellow "Aborted by user."
	exit 0
}

for s in "${STEPS[@]}"; do
	if ! step_enabled "$s"; then
		blue "── $s ── skipped (filtered)"
		continue
	fi
	if check_phase "$s" 2>/dev/null; then
		green "── $s ── already done, skipping"
		continue
	fi
	blue "── $s ── running"
	if ! confirm "  proceed with '$s'?"; then
		yellow "Aborted at '$s'. Re-run to resume."
		exit 0
	fi
	run_phase "$s"
	green "── $s ── done"
done

green "All done."
