# shellcheck shell=bash
# GFS pruning for snapshots pulled by syncoid.
# usage: syncoid-prune <prefix> <daily> <weekly> <monthly> <dataset>...
# Keeps the newest snapshot of each of the newest <daily> days, <weekly> ISO
# weeks and <monthly> months. Bucket-count based, so a stalled sync never ages
# out the incremental base, and a burst of source snapshots only displaces
# same-day ones. Future-dated snapshots (source clock skew) are kept but never
# fill a bucket. DRY_RUN=1 only prints.

prefix=$1
daily=$2
weekly=$3
monthly=$4
shift 4

now=$(date +%s)
rc=0

prune_dataset() {
	local ds=$1 line name ts day week month
	local -a snaps=()
	local -A keep=() days=() weeks=() months=()

	mapfile -t snaps < <(
		zfs list -H -p -t snapshot -d 1 -S creation -o name,creation "$ds" |
			awk -F '\t' -v p="$ds@$prefix" 'index($1, p) == 1'
	)

	for line in "${snaps[@]}"; do
		name=${line%%$'\t'*}
		ts=${line##*$'\t'}
		if ((ts > now)); then
			keep[$name]=1
			continue
		fi
		day=$(date -d "@$ts" +%F)
		week=$(date -d "@$ts" +%G-%V)
		month=$(date -d "@$ts" +%Y-%m)
		if [[ -z ${days[$day]:-} ]] && ((${#days[@]} < daily)); then
			days[$day]=1
			keep[$name]=1
		fi
		if [[ -z ${weeks[$week]:-} ]] && ((${#weeks[@]} < weekly)); then
			weeks[$week]=1
			keep[$name]=1
		fi
		if [[ -z ${months[$month]:-} ]] && ((${#months[@]} < monthly)); then
			months[$month]=1
			keep[$name]=1
		fi
	done

	for line in "${snaps[@]}"; do
		name=${line%%$'\t'*}
		if [[ -n ${keep[$name]:-} ]]; then
			continue
		fi
		echo "destroy $name"
		if [[ ${DRY_RUN:-0} != 1 ]] && ! zfs destroy "$name"; then
			echo "failed to destroy $name" >&2
			rc=1
		fi
	done
}

for ds in "$@"; do
	if ! zfs list -H -o name "$ds" >/dev/null 2>&1; then
		echo "skip $ds: not received yet"
		continue
	fi
	prune_dataset "$ds"
done

exit "$rc"
