#!/usr/bin/env bash
set -euo pipefail

# Helpers library
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

###############################################################################
# Dependency Check
###############################################################################

# Required tools per phase:
#   Phase 0: sed, awk (scaffold host config from templates)
#   Phase 1: ssh-keygen, ssh-to-age, sops, yq, jq
#   Phase 2: nix, nixos-anywhere (via nix run), ssh, scp, rsync
#   Phase 3: rsync, ssh
REQUIRED_TOOLS=(git ssh-keygen ssh-to-age sops yq jq nix rsync)

function check_dependencies() {
	local missing=()
	for cmd in "${REQUIRED_TOOLS[@]}"; do
		if ! command -v "$cmd" &>/dev/null; then
			missing+=("$cmd")
		fi
	done
	if [ ${#missing[@]} -gt 0 ]; then
		red "ERROR: Missing required tools: ${missing[*]}"
		red "Are you inside the nix dev shell? Run: nix develop"
		exit 1
	fi
}

check_dependencies

###############################################################################
# Variables & Defaults
###############################################################################

target_hostname=""
target_destination=""
target_user=${BOOTSTRAP_USER-$(whoami)}
ssh_port=${BOOTSTRAP_SSH_PORT-22}
persist_dir=""
disk_layout="ext4"
disk=""
disk2=""
nix_src_path="nix-src/"
git_root=$(git rev-parse --show-toplevel)
nix_secrets_dir=${NIX_SECRETS_DIR:-"${git_root}"/../nix-secrets}

# Phase control
phases="0,1,2,3" # default: all phases
migrate_mode=0
generate_user_age_key=1
run_rekey=1
target_installer=0
dry_run=0
builder=""

# Generated hardware config tracking
generated_hardware_config=0

# SSH key: agent first, then -k, then $BOOTSTRAP_SSH_KEY
opt_ssh_key=""

###############################################################################
# Usage
###############################################################################

function help_and_exit() {
	echo
	echo "Provision a new NixOS host: scaffold config, prepare secrets, install via nixos-anywhere, deploy full config."
	echo
	echo "USAGE: $0 -n <hostname> [OPTIONS]"
	echo
	echo "REQUIRED:"
	echo "  -n, --hostname <name>               Target hostname (must match nix-config host entry)"
	echo
	echo "PHASES:"
	echo "  -p, --phases <list>                  Comma-separated phases to run (default: 0,1,2,3)"
	echo "                                         0 = Scaffold config (host/default.nix, home, network.nix)"
	echo "                                         1 = Prepare secrets (generate SSH key, update sops)"
	echo "                                         2 = Install system (nixos-anywhere)"
	echo "                                         3 = Deploy full config (rsync + rebuild)"
	echo "  --migrate                            Phase 1 variant: restore SSH key from sops, not generate"
	echo
	echo "DISK (Phase 2):"
	echo "  --disk-layout <ext4|btrfs|zfs|zfs-mirror>"
	echo "                                       Disk layout type (default: ext4)"
	echo "  --disk <device>                      Primary disk device path"
	echo "                                       ZFS: use /dev/disk/by-id/..."
	echo "  --disk2 <device>                     Secondary disk (zfs-mirror only)"
	echo
	echo "BUILD (Phase 2):"
	echo "  --builder <mode>                     Override Phase 2 build strategy (default: system config)"
	echo '                                         no-remote   = local build with --option builders ""'
	echo "                                                       (skip remote ssh builders)"
	echo '                                         no-external = local build with --option external-builders "[]"'
	echo "                                                       (skip nix-vz-builder etc.)"
	echo "                                         on-target   = skip local build; nixos-anywhere --build-on remote"
	echo
	echo "CONNECTION (Phase 2/3):"
	echo "  -d, --destination <ip|domain>        Target IP or domain"
	echo "  -k, --ssh-key <path>                 SSH private key (default: SSH agent)"
	echo '  -u, --user <username>                Target user (default: BOOTSTRAP_USER or whoami)'
	echo "  --port <port>                        SSH port (default: 22)"
	echo
	echo "OPTIONS:"
	echo "  --target-installer                   Target is already in a NixOS installer (ISO/kexec'd), skip kexec"
	echo "  --no-user-age-key                    Skip user age key in Phase 1"
	echo "  --no-rekey                           Skip rekey in Phase 1"
	echo "  --impermanence                       Target uses /persist"
	echo "  --dry-run                            Show what would be done"
	echo "  --debug                              Enable set -x"
	echo "  -h, --help                           Show this help"
	echo
	echo "EXAMPLES:"
	echo "  # Full: ZFS mirror bare-metal"
	echo "  $0 -n Poecilia -d 192.168.1.50 --disk-layout zfs-mirror \\"
	echo "     --disk /dev/disk/by-id/nvme-A --disk2 /dev/disk/by-id/nvme-B"
	echo
	echo "  # Full: ext4 cloud VM"
	echo "  $0 -n mycloud -d 203.0.113.10 --disk /dev/vda"
	echo
	echo "  # Scaffold new host config only (interactive network prompts)"
	echo "  $0 -n newhost -p 0"
	echo
	echo "  # Prepare secrets only"
	echo "  $0 -n newhost -p 1"
	echo
	echo "  # Install + deploy (scaffold + secrets already done)"
	echo "  $0 -n newhost -d 192.168.1.100 -p 2,3 --disk /dev/sda"
	echo
	echo "  # Migrate: reinstall with existing SSH key"
	echo "  $0 -n Pseudomugil -d 192.168.1.60 --migrate --disk-layout zfs-mirror \\"
	echo "     --disk /dev/disk/by-id/nvme-A --disk2 /dev/disk/by-id/nvme-B"
	exit 0
}

###############################################################################
# Argument Parsing
###############################################################################

while [[ $# -gt 0 ]]; do
	case "$1" in
	-n | --hostname)
		shift
		target_hostname=$1
		;;
	-d | --destination)
		shift
		target_destination=$1
		;;
	-u | --user)
		shift
		target_user=$1
		;;
	-k | --ssh-key)
		shift
		opt_ssh_key=$1
		;;
	--port)
		shift
		ssh_port=$1
		;;
	--disk-layout)
		shift
		disk_layout=$1
		;;
	--disk)
		shift
		disk=$1
		;;
	--disk2)
		shift
		disk2=$1
		;;
	--builder)
		shift
		builder=$1
		;;
	-p | --phases)
		shift
		phases=$1
		;;
	--migrate)
		migrate_mode=1
		;;
	--target-installer | --no-kexec)
		target_installer=1
		;;
	--no-user-age-key)
		generate_user_age_key=0
		;;
	--no-rekey)
		run_rekey=0
		;;
	--impermanence)
		persist_dir="/persist"
		;;
	--dry-run)
		dry_run=1
		;;
	--debug)
		set -x
		;;
	-h | --help) help_and_exit ;;
	*)
		red "ERROR: Invalid option: $1"
		help_and_exit
		;;
	esac
	shift
done

###############################################################################
# Validation
###############################################################################

if [ -z "$target_hostname" ]; then
	red "ERROR: -n/--hostname is required"
	help_and_exit
fi

# Parse --phases into individual flags
run_scaffold=0
run_prepare=0
run_install=0
run_deploy=0
IFS=',' read -ra phase_list <<<"$phases"
for p in "${phase_list[@]}"; do
	case "$p" in
	0) run_scaffold=1 ;;
	1) run_prepare=1 ;;
	2) run_install=1 ;;
	3) run_deploy=1 ;;
	*)
		red "ERROR: Invalid phase '$p'. Must be 0, 1, 2, or 3"
		exit 1
		;;
	esac
done

# --migrate reinstalls an existing host: skip scaffold, and phase 1 restores
# the SSH key from sops instead of generating one (migrate_extract_ssh_key).
if [ "$migrate_mode" -eq 1 ]; then
	run_scaffold=0
	run_prepare=0
fi

# Validate disk layout
case "$disk_layout" in
ext4 | btrfs | zfs | zfs-mirror) ;;
*)
	red "ERROR: Invalid --disk-layout '$disk_layout'. Must be one of: ext4, btrfs, zfs, zfs-mirror"
	exit 1
	;;
esac

# Validate builder strategy
case "$builder" in
"" | no-remote | no-external | on-target) ;;
*)
	red "ERROR: Invalid --builder '$builder'. Must be one of: no-remote, no-external, on-target"
	exit 1
	;;
esac

# Validate zfs-mirror requires disk2
if [ "$disk_layout" = "zfs-mirror" ] && [ -n "$disk" ] && [ -z "$disk2" ]; then
	red "ERROR: --disk-layout zfs-mirror requires --disk2"
	exit 1
fi

# Phase 2/3 require destination
if { [ "$run_install" -eq 1 ] || [ "$run_deploy" -eq 1 ]; } && [ -z "$target_destination" ]; then
	red "ERROR: -d/--destination is required for phase 2/3"
	exit 1
fi

# Phase 2 requires disk
if [ "$run_install" -eq 1 ] && [ -z "$disk" ]; then
	red "ERROR: --disk is required for phase 2"
	exit 1
fi

###############################################################################
# SSH Setup
###############################################################################

# SSH key priority: agent (default) > -k explicit override
# Only use a key file when explicitly passed via -k. This ensures SSH agent is always tried first.
ssh_key="$opt_ssh_key"

# Expand tilde — bash does not expand ~ inside variables
ssh_key="${ssh_key/#\~/$HOME}"

# Validate: if the key file doesn't exist, fall back to SSH agent
ssh_identity=""
if [ -n "$ssh_key" ]; then
	if [ -f "$ssh_key" ]; then
		ssh_identity="-i $ssh_key"
		green "Using SSH key: $ssh_key"
	else
		red "SSH key '$ssh_key' not found"
		exit 1
	fi
fi

# Build SSH commands (only when destination is known)
ssh_cmd=""
ssh_root_cmd=""
#scp_cmd=""

# SSH ControlMaster socket for connection multiplexing.
# %r@%h:%p is expanded by ssh to user@host:port, ensuring separate sockets
# per user/host/port combination.
ssh_control_path="/tmp/ssh-provision-$$-%r@%h:%p"

function setup_ssh_commands() {
	local ssh_mux="-oControlMaster=auto -oControlPath=${ssh_control_path} -oControlPersist=60"
	ssh_cmd="ssh \
		${ssh_mux} \
		-oport=${ssh_port} \
		-oForwardAgent=yes \
		-oStrictHostKeyChecking=no \
		-oUserKnownHostsFile=/dev/null \
		${ssh_identity} \
		-t ${target_user}@${target_destination}"
	# shellcheck disable=SC2001
	ssh_root_cmd=$(echo "$ssh_cmd" | sed "s|${target_user}@|root@|")
	#scp_cmd="scp ${ssh_mux} -oport=${ssh_port} -oStrictHostKeyChecking=no ${ssh_identity}"
}

# Close ControlMaster sockets on script exit
function cleanup_ssh() {
	if [ -n "$target_destination" ]; then
		ssh -oControlPath="${ssh_control_path}" -O exit "${target_user}@${target_destination}" 2>/dev/null || true
		ssh -oControlPath="${ssh_control_path}" -O exit "root@${target_destination}" 2>/dev/null || true
	fi
}
trap cleanup_ssh EXIT

if [ -n "$target_destination" ]; then
	setup_ssh_commands
fi

###############################################################################
# Sync helper
###############################################################################

function rsync_config() {
	# $1 = user, $2 = source
	# NOTE: ForwardAgent=yes is critical here. With ControlMaster=auto, the first
	# connection creates the master. If rsync creates it WITHOUT ForwardAgent,
	# all subsequent multiplexed sessions (including nixos-rebuild) lose agent
	# forwarding — even if they specify ForwardAgent=yes themselves.
	rsync -av --mkpath --filter=':- .gitignore' \
		-e "ssh -oControlMaster=auto -oControlPath=${ssh_control_path} -oForwardAgent=yes -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null -l $1 -oport=${ssh_port} ${ssh_identity}" \
		"$2" "$1@${target_destination}:${nix_src_path}"
}

###############################################################################
# Secure temp directory (prefer /dev/shm on Linux for in-memory storage)
###############################################################################

function make_secure_temp() {
	mktemp -d -p /dev/shm 2>/dev/null || mktemp -d
}

###############################################################################
# Phase 0: Scaffold Host Config
###############################################################################

# Create hosts/nixos/<host>/default.nix, home/channinghe/<host>.nix and a
# network.nix entry from templates. Network details are prompted interactively.
# Skips (does not abort) if the host dir already exists, so re-runs are safe.
function scaffold_host() {
	local host_template="${git_root}/hosts/host-template.nix.placeholder"
	local home_template="${git_root}/home/channinghe/home-template.nix.placeholder"
	local network_nix="${nix_secrets_dir}/nix/network.nix"
	local host_dir="${git_root}/hosts/nixos/${target_hostname}"
	local home_file="${git_root}/home/channinghe/${target_hostname}.nix"

	if [ -d "$host_dir" ]; then
		yellow "Host config already exists: hosts/nixos/${target_hostname} — skipping scaffold."
		return 0
	fi

	if [ ! -f "$host_template" ]; then
		red "Host template not found: ${host_template}"
		exit 1
	fi
	if [ ! -f "$home_template" ]; then
		red "Home template not found: ${home_template}"
		exit 1
	fi

	# Interactive network prompts (no equivalent provision flags).
	local ip4 gateway4 dns interface host_id custom_id
	echo -en "\x1B[34m[?] IPv4 address (e.g. 10.1.10.100): \x1B[0m"
	read -r ip4
	[ -z "$ip4" ] && {
		red "IPv4 address is required."
		exit 1
	}

	echo -en "\x1B[34m[?] IPv4 gateway (e.g. 10.1.10.1): \x1B[0m"
	read -r gateway4
	[ -z "$gateway4" ] && {
		red "IPv4 gateway is required."
		exit 1
	}

	echo -en "\x1B[34m[?] DNS server (default: 10.1.10.2): \x1B[0m"
	read -r dns
	dns="${dns:-10.1.10.2}"

	echo -en "\x1B[34m[?] Network interface name (e.g. enp3s0): \x1B[0m"
	read -r interface
	[ -z "$interface" ] && {
		red "Network interface is required."
		exit 1
	}

	host_id=$(head -c4 /dev/urandom | od -A none -t x4 | xargs)
	blue "Generated hostId: ${host_id}"
	echo -en "\x1B[34m[?] Press Enter to accept, or type a custom hostId: \x1B[0m"
	read -r custom_id
	[ -n "$custom_id" ] && host_id="$custom_id"

	echo
	blue "====== Scaffold Summary ======"
	echo "  Hostname:   ${target_hostname}"
	echo "  IPv4:       ${ip4}"
	echo "  Gateway:    ${gateway4}"
	echo "  DNS:        ${dns}"
	echo "  Interface:  ${interface}"
	echo "  Host ID:    ${host_id}"
	echo "  Will create:"
	echo "    hosts/nixos/${target_hostname}/default.nix"
	echo "    home/channinghe/${target_hostname}.nix"
	echo "    network.nix entry in ${network_nix}"
	echo

	if [ "$dry_run" -eq 1 ]; then
		yellow "[DRY-RUN] Would scaffold the files listed above."
		return 0
	fi

	if ! yes_or_no "Proceed with scaffold?"; then
		yellow "Scaffold aborted."
		exit 0
	fi

	# 1. Host config from template (substitute FIXME placeholders).
	green "Creating host config..."
	mkdir -p "$host_dir"
	sed \
		-e "s/hostName = \"foo\"/hostName = \"${target_hostname}\"/" \
		-e "s/hostId = \"xxxxx\"/hostId = \"${host_id}\"/" \
		-e "s/matchConfig\.Name = \"xxxxx\"/matchConfig.Name = \"${interface}\"/" \
		-e '/# \!\!\!\[FIXME\]\!\!\!/d' \
		"$host_template" >"${host_dir}/default.nix"
	green "Created hosts/nixos/${target_hostname}/default.nix"

	# 2. Home-manager config from template.
	cp "$home_template" "$home_file"
	green "Created home/channinghe/${target_hostname}.nix"

	# 3. Inject network entry into nix-secrets/nix/network.nix.
	if [ ! -f "$network_nix" ]; then
		red "nix-secrets network.nix not found: ${network_nix}"
		yellow "Skipping network injection. Add the entry manually."
	elif grep -q "^[[:space:]]*${target_hostname} = {" "$network_nix"; then
		yellow "Host '${target_hostname}' already in network.nix, skipping injection."
	else
		local tmp_file
		tmp_file=$(mktemp)
		NH_HOSTNAME="$target_hostname" NH_IP4="$ip4" NH_GATEWAY4="$gateway4" NH_DNS="$dns" \
			awk '/# Other hosts/ {
				printf "      %s = {\n", ENVIRON["NH_HOSTNAME"]
				printf "        ip4 = \"%s\";\n", ENVIRON["NH_IP4"]
				printf "        gateway4 = \"%s\";\n", ENVIRON["NH_GATEWAY4"]
				printf "        dns = [ \"%s\" ];\n", ENVIRON["NH_DNS"]
				printf "      };\n"
			}
			{ print }' \
			"$network_nix" >"$tmp_file"
		mv "$tmp_file" "$network_nix"
		green "Added network entry to ${network_nix}"
	fi

	green "Host scaffold complete for ${target_hostname}."
}

###############################################################################
# Phase 1: Prepare Secrets
###############################################################################

function prepare_secrets() {
	green "===== Phase 1: Preparing secrets for ${target_hostname} ====="

	local secure_temp
	secure_temp=$(make_secure_temp)
	# Cleanup secure temp on function exit
	# shellcheck disable=SC2064
	trap "rm -rf '$secure_temp'" RETURN

	local secret_file="${nix_secrets_dir}/secrets/${target_hostname}.yaml"
	local config="${nix_secrets_dir}/.sops.yaml"

	# 1. Generate SSH host key in secure temp (in-memory on Linux)
	green "Generating SSH host key pair for ${target_hostname}"
	if [ "$dry_run" -eq 1 ]; then
		yellow "[DRY-RUN] Would generate ssh-keygen -t ed25519 in ${secure_temp}"
	else
		ssh-keygen -t ed25519 -f "${secure_temp}/key" -C "${target_user}@${target_hostname}" -N "" -q
	fi

	# 2. Derive age public key locally (no remote scan needed)
	green "Deriving age public key from SSH host key"
	if [ "$dry_run" -eq 1 ]; then
		yellow "[DRY-RUN] Would run ssh-to-age -i ${secure_temp}/key.pub"
		local host_age_key="age1dry_run_placeholder"
	else
		local host_age_key
		host_age_key=$(ssh-to-age -i "${secure_temp}/key.pub")
		if grep -qv '^age1' <<<"$host_age_key"; then
			red "Generated age key does not match expected format."
			yellow "Result: $host_age_key"
			exit 1
		fi
		green "Host age key: ${host_age_key}"
	fi

	# 3. Update .sops.yaml with host age key and creation rules
	green "Updating nix-secrets/.sops.yaml"
	if [ "$dry_run" -eq 1 ]; then
		yellow "[DRY-RUN] Would update .sops.yaml with host age key and creation rules"
	else
		sops_update_age_key "hosts" "$target_hostname" "$host_age_key"
		sops_add_creation_rules "$target_user" "$target_hostname"
	fi

	# 4. Write SSH key into sops — private key never touches persistent disk
	green "Writing SSH host key into sops-encrypted secrets file"
	if [ "$dry_run" -eq 1 ]; then
		yellow "[DRY-RUN] Would write SSH key to ${secret_file}"
	else
		if [ ! -f "$secret_file" ]; then
			# New file: build plaintext in secure temp (RAM on Linux), encrypt with correct filename
			green "Creating new secrets file: ${secret_file}"
			mkdir -p "$(dirname "$secret_file")"
			local plaintext="${secure_temp}/plaintext.yaml"
			{
				echo "keys:"
				echo "  ssh_host_ed25519_key: |"
				sed 's/^/    /' "${secure_temp}/key"
				echo "  ssh_host_ed25519_key_pub: \"$(cat "${secure_temp}/key.pub")\""
			} >"$plaintext"
			# --input-type/--output-type required since sops can't infer from stdin path
			# --filename-override tells sops which creation_rule path_regex to match
			sops --config "$config" \
				--input-type yaml --output-type yaml \
				--filename-override "secrets/${target_hostname}.yaml" \
				-e "$plaintext" >"$secret_file"
			rm -f "$plaintext"
		else
			# Existing file: update via sops --set with JSON-encoded multiline
			green "Updating existing secrets file: ${secret_file}"
			local private_json public_json
			private_json=$(jq -Rs . <"${secure_temp}/key")
			public_json=$(jq -Rs . <"${secure_temp}/key.pub")
			sops --config "$config" --set '["keys"]["ssh_host_ed25519_key"] '"$private_json" "$secret_file"
			sops --config "$config" --set '["keys"]["ssh_host_ed25519_key_pub"] '"$public_json" "$secret_file"
		fi
	fi

	# 5. Secure cleanup of plaintext key material
	rm -f "${secure_temp}/key" "${secure_temp}/key.pub"

	# 6. Optional: generate user age key
	if [ "$generate_user_age_key" -eq 1 ]; then
		if yes_or_no "Generate user age key for ${target_hostname}?"; then
			if [ "$dry_run" -eq 1 ]; then
				yellow "[DRY-RUN] Would generate user age key"
			else
				sops_setup_user_age_key "$target_user" "$target_hostname"
			fi
		fi
	fi

	# 7. Copy user password from shared.yaml to host secrets.
	# NixOS user config (nixos.nix) reads passwords/<username> from the host's
	# secrets file. Without this, the user has no login password after Phase 3.
	green "Copying user password from shared.yaml to ${target_hostname} secrets"
	if [ "$dry_run" -eq 1 ]; then
		yellow "[DRY-RUN] Would copy passwords/${target_user} from shared.yaml"
	else
		local shared_file="${nix_secrets_dir}/secrets/shared.yaml"
		if [ -f "$shared_file" ] && [ -f "$secret_file" ]; then
			if sops --config "$config" -d --extract '["passwords"]["'"$target_user"'"]' "$shared_file" >/dev/null 2>&1; then
				local pw_json
				pw_json=$(sops --config "$config" -d --extract '["passwords"]["'"$target_user"'"]' "$shared_file" | jq -Rs .)
				sops --config "$config" --set '["passwords"]["'"$target_user"'"] '"$pw_json" "$secret_file"
				green "Copied passwords/${target_user} to secrets/${target_hostname}.yaml"
			else
				yellow "WARNING: passwords/${target_user} not found in shared.yaml. Skipping."
			fi
		else
			yellow "WARNING: shared.yaml or host secrets file missing. Skipping password copy."
		fi
	fi

	# 8. Rekey + update flake
	if [ "$run_rekey" -eq 1 ]; then
		green "Rekeying secrets and updating flake input"
		if [ "$dry_run" -eq 1 ]; then
			yellow "[DRY-RUN] Would run: just rekey && nix flake update nix-secrets"
		else
			just rekey
			green "Remember to update flake input to pick up new .sops.yaml"
			#nix flake update nix-secrets
		fi
	fi

	green "Phase 1 complete."
}

###############################################################################
# Phase 1-M: Migrate mode — extract existing SSH key from sops
###############################################################################

function migrate_extract_ssh_key() {
	green "===== Migrate: Extracting SSH host key from sops for ${target_hostname} ====="

	local secret_file="${nix_secrets_dir}/secrets/${target_hostname}.yaml"
	local config="${nix_secrets_dir}/.sops.yaml"

	if [ ! -f "$secret_file" ]; then
		red "ERROR: Secrets file not found: ${secret_file}"
		red "Cannot migrate without existing sops-encrypted SSH host key."
		exit 1
	fi

	# Verify the SSH key exists in the secrets file
	if ! sops --config "$config" -d --extract '["keys"]["ssh_host_ed25519_key"]' "$secret_file" >/dev/null 2>&1; then
		red "ERROR: keys.ssh_host_ed25519_key not found in ${secret_file}"
		red "The secrets file exists but doesn't contain an SSH host key."
		exit 1
	fi

	green "SSH host key found in sops. Will be extracted during install phase."
}

###############################################################################
# Phase 2: Install System
###############################################################################

function install_system() {
	green "===== Phase 2: Installing NixOS on ${target_hostname} at ${target_destination} ====="

	# Pre-flight: stale hardware-configuration.nix breaks the build silently — flake.nix
	# auto-imports it whenever the file exists, and wrong disk UUIDs / kernel modules
	# from a previous machine fail at evaluation or first boot. Force a decision now.
	local hw_config="${git_root}/hosts/nixos/${target_hostname}/hardware-configuration.nix"
	if [ -f "$hw_config" ]; then
		echo
		yellow "Found existing hardware-configuration.nix:"
		yellow "  hosts/nixos/${target_hostname}/hardware-configuration.nix"
		yellow "It will be auto-imported by the flake. If it does not match the target hardware,"
		yellow "the build or first boot will fail."
		echo
		echo "  [k]eep   — use as-is (only if you know it matches the target)"
		echo "  [b]ackup — move to hardware-configuration.nix.bak; Phase 3 regenerates from target (recommended)"
		echo "  [a]bort  — exit"
		while true; do
			echo -en "\x1B[34m[?] Action [k/b/a]: \x1B[0m"
			local hw_action=""
			read -r hw_action
			case "$hw_action" in
			k | K)
				green "Keeping existing hardware-configuration.nix"
				break
				;;
			b | B)
				if [ "$dry_run" -eq 1 ]; then
					yellow "[DRY-RUN] Would move ${hw_config} → ${hw_config}.bak"
				else
					mv "$hw_config" "${hw_config}.bak"
					green "Moved to: hosts/nixos/${target_hostname}/hardware-configuration.nix.bak"
				fi
				break
				;;
			a | A)
				red "Aborted by user."
				exit 1
				;;
			*) yellow "Please answer k / b / a" ;;
			esac
		done
		echo
	fi

	local secret_file="${nix_secrets_dir}/secrets/${target_hostname}.yaml"
	local config="${nix_secrets_dir}/.sops.yaml"

	# 1. Extract SSH key from sops to secure temp (sops is the single source of truth)
	local secure_temp
	secure_temp=$(make_secure_temp)
	# shellcheck disable=SC2064
	trap "rm -rf '$secure_temp'" RETURN

	green "Extracting SSH host key from sops"
	if [ "$dry_run" -eq 1 ]; then
		yellow "[DRY-RUN] Would extract SSH key from sops to secure temp"
	else
		install -d -m755 "${secure_temp}/${persist_dir}/etc/ssh"
		sops --config "$config" -d --extract '["keys"]["ssh_host_ed25519_key"]' "$secret_file" \
			>"${secure_temp}/${persist_dir}/etc/ssh/ssh_host_ed25519_key"
		sops --config "$config" -d --extract '["keys"]["ssh_host_ed25519_key_pub"]' "$secret_file" \
			>"${secure_temp}/${persist_dir}/etc/ssh/ssh_host_ed25519_key.pub"
		chmod 600 "${secure_temp}/${persist_dir}/etc/ssh/ssh_host_ed25519_key"
	fi

	# 2. Clear stale known_hosts entries
	green "Wiping known_hosts entries for ${target_destination}"
	sed -i.bak "/${target_hostname}/d; /${target_destination}/d" ~/.ssh/known_hosts 2>/dev/null || true

	# 3. Add current host fingerprint
	green "Adding ssh host fingerprint at ${target_destination} to ~/.ssh/known_hosts"
	ssh-keyscan -p "$ssh_port" "$target_destination" 2>/dev/null | grep -v '^#' >>~/.ssh/known_hosts || true

	# 4. Build system with env vars (--impure enables builtins.getEnv)
	# NOTE: hardware-configuration.nix is optional at this stage.
	# If it exists, it will be included; if not, the minimal config is sufficient.
	# It will be generated after reboot when the target is running NixOS.
	green "Preparing NixOS build for ${target_hostname} (layout: ${disk_layout}, disk: ${disk}, builder: ${builder:-default})"
	export NIXOS_HOSTNAME="$target_hostname"
	export NIXOS_DISK_LAYOUT="$disk_layout"
	export NIXOS_DISK="$disk"
	export NIXOS_DISK2="$disk2"

	# Translate --builder mode into extra nix options for the local nix build
	# (used by no-remote / no-external) and into the nixos-anywhere args
	# (used by on-target).
	local -a nix_build_opts=()
	case "$builder" in
	no-remote)
		# `builders` is a whitespace-separated list; empty string = no remote ssh builders.
		nix_build_opts+=(--option builders "")
		;;
	no-external)
		# `external-builders` is a JSON array; the empty value must be "[]",
		# not "" (which fails JSON parse and silently falls back to nix.conf).
		nix_build_opts+=(--option external-builders "[]")
		;;
	esac

	if [ "$dry_run" -eq 1 ]; then
		if [ "$builder" = "on-target" ]; then
			yellow "[DRY-RUN] Would run: nixos-anywhere --flake ./nixos-anywhere#${target_hostname} --build-on remote root@${target_destination}"
		else
			yellow "[DRY-RUN] Would run: nix build ${nix_build_opts[*]} --impure ./nixos-anywhere#...diskoScript"
			yellow "[DRY-RUN] Would run: nix build ${nix_build_opts[*]} --impure ./nixos-anywhere#...toplevel"
			yellow "[DRY-RUN] Would run: nixos-anywhere --store-paths ... root@${target_destination}"
		fi
	else
		# Common nixos-anywhere arguments
		# If user provided -k, pass it via -i; otherwise let nixos-anywhere
		# handle its own temp key generation (requires root@ to be accessible).
		local -a na_args=(
			--extra-files "$secure_temp"
			--ssh-port "$ssh_port"
		)

		if [ "$builder" = "on-target" ]; then
			green "Skipping local nix build — target ${target_destination} will evaluate+realise the system"
			yellow "NOTE: nixos-anywhere#${target_hostname} reads NIXOS_HOSTNAME/NIXOS_DISK_LAYOUT/NIXOS_DISK via builtins.getEnv."
			yellow "      With --build-on remote, the remote nix invocation must also see these env vars,"
			yellow "      otherwise the flake will evaluate to an empty nixosConfigurations set."
			na_args+=(
				--flake "${git_root}/nixos-anywhere#${target_hostname}"
				--build-on remote
			)
		else
			if [ "${#nix_build_opts[@]}" -gt 0 ]; then
				green "Building NixOS system locally (${nix_build_opts[*]})"
			else
				green "Building NixOS system locally"
			fi
			local disko_script nixos_system
			disko_script=$(nix build ${nix_build_opts[@]+"${nix_build_opts[@]}"} --impure --no-link --print-out-paths \
				"${git_root}/nixos-anywhere#nixosConfigurations.${target_hostname}.config.system.build.diskoScript")
			nixos_system=$(nix build ${nix_build_opts[@]+"${nix_build_opts[@]}"} --impure --no-link --print-out-paths \
				"${git_root}/nixos-anywhere#nixosConfigurations.${target_hostname}.config.system.build.toplevel")

			green "disko-script: ${disko_script}"
			green "nixos-system: ${nixos_system}"

			na_args+=(--store-paths "$disko_script" "$nixos_system")
		fi

		if [ -n "$ssh_key" ]; then
			na_args+=(-i "$ssh_key")
		fi

		if [ "$target_installer" -eq 1 ]; then
			# Installer mode: target is already in a NixOS installer environment
			# (e.g. custom NixOS ISO, or previously kexec'd). Disks are safe to
			# format directly. The reboot phase handles unmount + ZFS export.
			green "Running nixos-anywhere (installer mode) on ${target_hostname} at ${target_destination}"
			SHELL=/bin/sh nix run github:nix-community/nixos-anywhere -- \
				"${na_args[@]}" \
				--phases "disko,install,reboot" \
				root@"$target_destination"
		else
			# Kexec mode: target is any non-NixOS environment (live Linux image,
			# running VPS, etc.). Must kexec into NixOS installer first.
			# Split into two invocations: kexec may change the IP
			# (new MAC → new DHCP lease).
			green "Phase 2a: kexec into NixOS installer on ${target_destination}"
			SHELL=/bin/sh nix run github:nix-community/nixos-anywhere -- \
				"${na_args[@]}" \
				--phases kexec \
				root@"$target_destination"

			# After kexec, IP may have changed (new MAC → new DHCP lease).
			# Loop: prompt IP → test SSH → retry until reachable.
			echo
			yellow "kexec complete. Target is rebooting into NixOS installer."
			while true; do
				echo -en "\x1B[34m[?] Target IP [${target_destination}]: \x1B[0m"
				read -r new_ip
				if [ -n "$new_ip" ] && [ "$new_ip" != "$target_destination" ]; then
					green "Updating target IP: ${target_destination} → ${new_ip}"
					target_destination="$new_ip"
					setup_ssh_commands
				fi

				yellow "Waiting for ${target_destination}:${ssh_port} to become reachable..."
				local reachable=0
				for _ in $(seq 1 15); do
					if ssh-keyscan -p "$ssh_port" "$target_destination" 2>/dev/null | grep -q ssh; then
						reachable=1
						break
					fi
					sleep 2
				done

				if [ "$reachable" -eq 1 ]; then
					green "SSH is up on ${target_destination}:${ssh_port}"
					break
				else
					yellow "Cannot reach ${target_destination}:${ssh_port} after 30s."
					yellow "Possible causes: wrong IP, host still rebooting, or firewall."
					yellow "Enter a new IP or press Enter to retry the same address."
				fi
			done

			# Run disko + install + reboot. The reboot phase properly unmounts
			# filesystems, exports ZFS pools, then reboots into the installed system.
			green "Phase 2b: disko + install + reboot on ${target_destination}"
			SHELL=/bin/sh nix run github:nix-community/nixos-anywhere -- \
				"${na_args[@]}" \
				--phases "disko,install,reboot" \
				root@"$target_destination"
		fi
	fi

	# Post-install: wait for the installed system to come online after reboot.
	# nixos-anywhere's reboot phase has already initiated the reboot.
	# IP may change (new MAC → fresh DHCP lease) and the SSH host key will change
	# (installed system uses our sops-injected key), so mirror the kexec loop:
	# prompt for the post-reboot IP, then probe SSH.
	green "Waiting for ${target_hostname} to boot into the installed system..."

	# Close stale ControlMaster sockets (old connection is dead after reboot)
	cleanup_ssh

	# Clear stale known_hosts (installer/old key is no longer valid)
	sed -i.bak "/${target_hostname}/d; /${target_destination}/d" ~/.ssh/known_hosts 2>/dev/null || true

	echo
	yellow "Target is rebooting into the installed NixOS system."
	local boot_ok=0
	while true; do
		echo -en "\x1B[34m[?] Target IP [${target_destination}]: \x1B[0m"
		local new_ip=""
		read -r new_ip
		if [ -n "$new_ip" ] && [ "$new_ip" != "$target_destination" ]; then
			green "Updating target IP: ${target_destination} → ${new_ip}"
			target_destination="$new_ip"
			setup_ssh_commands
			sed -i.bak "/${target_destination}/d" ~/.ssh/known_hosts 2>/dev/null || true
		fi

		yellow "Waiting for ${target_destination}:${ssh_port} to become reachable (up to 3 min)..."
		boot_ok=0
		for _ in $(seq 1 60); do
			if ssh-keyscan -p "$ssh_port" "$target_destination" 2>/dev/null | grep -q ssh; then
				boot_ok=1
				break
			fi
			sleep 3
		done

		if [ "$boot_ok" -eq 1 ]; then
			green "SSH is up on ${target_destination}:${ssh_port}"
			break
		fi

		yellow "Cannot reach ${target_destination}:${ssh_port} after 3 min."
		yellow "Possible causes: wrong IP, system still booting, or network/firewall issue."
		if ! yes_or_no "Try again with a different (or same) IP?"; then
			yellow "Skipping verification; proceeding to Phase 3 anyway."
			break
		fi
	done

	if [ "$boot_ok" -eq 1 ]; then
		# Add the installed system's host key to known_hosts
		ssh-keyscan -p "$ssh_port" "$target_destination" 2>/dev/null | grep -v '^#' >>~/.ssh/known_hosts || true

		# Verify we're talking to the installed system, not the installer.
		# Use the regular user (not root) — hostname doesn't need privileges.
		local remote_hostname
		remote_hostname=$($ssh_root_cmd "hostname" 2>/dev/null) ||
			remote_hostname=$($ssh_cmd "hostname" 2>/dev/null) || remote_hostname=""
		if [ "$remote_hostname" = "$target_hostname" ]; then
			green "Target ${target_hostname} is online and verified."
		else
			yellow "WARNING: Remote hostname '${remote_hostname}' does not match expected '${target_hostname}'."
			yellow "The system may still be booting or the hostname config differs."
		fi
	fi

	green "Phase 2 complete."
}

###############################################################################
# Phase 3: Deploy Full Config
###############################################################################

function deploy_config() {
	green "===== Phase 3: Deploying full config to ${target_hostname} ====="

	# 1. Wait for target to be reachable via SSH
	green "Waiting for ${target_destination}:${ssh_port} to become reachable..."
	local boot_reachable=0
	for _ in $(seq 1 60); do
		if ssh-keyscan -p "$ssh_port" "$target_destination" 2>/dev/null | grep -q ssh; then
			boot_reachable=1
			break
		fi
		sleep 3
	done
	if [ "$boot_reachable" -eq 0 ]; then
		yellow "WARNING: ${target_destination}:${ssh_port} is not reachable after 3 min."
		if ! yes_or_no "Continue anyway? (no exits)"; then
			exit 0
		fi
	fi

	# 2. Update known_hosts
	green "Adding ${target_destination}'s ssh host fingerprint to ~/.ssh/known_hosts"
	ssh-keyscan -p "$ssh_port" "$target_destination" 2>/dev/null | grep -v '^#' >>~/.ssh/known_hosts || true

	# 3. Handle impermanence
	if [ -n "$persist_dir" ]; then
		green "Copying machine-id and SSH keys to ${persist_dir}"
		if [ "$dry_run" -eq 0 ]; then
			$ssh_root_cmd "cp /etc/machine-id ${persist_dir}/etc/machine-id || true"
			$ssh_root_cmd "cp -R /etc/ssh/ ${persist_dir}/etc/ssh/ || true"
		fi
	fi

	# 4. Generate hardware-configuration.nix (target is now running NixOS)
	local hw_config="${git_root}/hosts/nixos/${target_hostname}/hardware-configuration.nix"
	if [ ! -f "$hw_config" ]; then
		if yes_or_no "Generate hardware-configuration.nix for ${target_hostname}?"; then
			green "Generating hardware-configuration.nix on ${target_hostname}"
			if [ "$dry_run" -eq 1 ]; then
				yellow "[DRY-RUN] Would generate hardware-configuration.nix on target"
			else
				# Ensure the host dir exists; the redirect below would otherwise
				# fail before nixos-generate-config even runs.
				mkdir -p "$(dirname "$hw_config")"
				$ssh_root_cmd "nixos-generate-config --show-hardware-config" \
					>"$hw_config" 2>/dev/null || {
					red "Failed to generate hardware-configuration.nix"
					red "You may need to create it manually."
				}
				if [ -f "$hw_config" ] && [ -s "$hw_config" ]; then
					generated_hardware_config=1
					green "hardware-configuration.nix saved to: hosts/nixos/${target_hostname}/"
				fi
			fi
		fi
	fi

	# 4b. Detect primary network interface name on the target.
	# Hosts using systemd-networkd need the correct interface name in matchConfig.Name.
	if [ "$dry_run" -eq 0 ]; then
		local remote_iface
		remote_iface=$($ssh_root_cmd "ip -o -4 addr show scope global | awk '{print \$2}' | head -1" 2>/dev/null | tr -d '\r\n') || remote_iface=""
		if [ -n "$remote_iface" ]; then
			local host_config="${git_root}/hosts/nixos/${target_hostname}/default.nix"
			if [ -f "$host_config" ] && grep -q 'matchConfig\.Name' "$host_config"; then
				local current_iface
				current_iface=$(grep 'matchConfig\.Name' "$host_config" | head -1 | sed 's/.*"\(.*\)".*/\1/')
				if [ "$current_iface" != "$remote_iface" ]; then
					yellow "Network interface mismatch: config has '${current_iface}', target has '${remote_iface}'"
					if yes_or_no "Update matchConfig.Name from '${current_iface}' to '${remote_iface}' in default.nix?"; then
						sed -i.bak "s|matchConfig.Name = \"${current_iface}\"|matchConfig.Name = \"${remote_iface}\"|" "$host_config"
						rm -f "${host_config}.bak"
						green "Updated matchConfig.Name to '${remote_iface}' in hosts/nixos/${target_hostname}/default.nix"
					fi
				else
					green "Network interface '${remote_iface}' matches config."
				fi
			else
				blue "Target primary network interface: ${remote_iface}"
				blue "If your host config uses systemd-networkd, set matchConfig.Name = \"${remote_iface}\";"
			fi
		fi
	fi

	# 5. Stage any new/modified files so the flake can see them.
	# Nix flake evaluation only includes git-tracked files in the store copy.
	if [ "$generated_hardware_config" -eq 1 ] || [ -n "$(git -C "$git_root" diff --name-only "hosts/nixos/${target_hostname}/" 2>/dev/null)" ]; then
		green "Staging changed files under hosts/nixos/${target_hostname}/"
		git -C "$git_root" add "hosts/nixos/${target_hostname}/" 2>/dev/null || true
	fi

	# 6. Sync and rebuild
	if yes_or_no "Copy nix-config to ${target_hostname}?"; then
		green "Copying nix-config to ${target_hostname}"
		if [ "$dry_run" -eq 1 ]; then
			yellow "[DRY-RUN] Would rsync nix-config to target"
		else
			rsync_config "$target_user" "${git_root}/../nix-config"
		fi

		if yes_or_no "Rebuild ${target_hostname} immediately?"; then
			green "Rebuilding nix-config on ${target_hostname}"
			if [ "$dry_run" -eq 1 ]; then
				yellow "[DRY-RUN] Would run nixos-rebuild on target"
			else
				$ssh_cmd "cd ${nix_src_path}nix-config && sudo --preserve-env=SSH_AUTH_SOCK nixos-rebuild --show-trace --flake .#${target_hostname} switch"
			fi
		fi
	else
		echo
		green "NixOS was successfully installed!"
		echo "Post-install instructions:"
		echo "  To copy config:  just sync ${target_user} ${target_destination}"
		echo "  To rebuild:      ssh to ${target_hostname}, then:"
		echo "    cd ${nix_src_path}nix-config"
		echo "    sudo nixos-rebuild --show-trace --flake .#${target_hostname} switch"
		echo
	fi

	if [ "$generated_hardware_config" -eq 1 ]; then
		green "hardware-configuration.nix was generated and staged: hosts/nixos/${target_hostname}/hardware-configuration.nix"
		green "Remember to commit it to nix-config after provisioning is done."
	fi

	green "Phase 3 complete."
}

###############################################################################
# Main
###############################################################################

green "=========================================="
green "NixOS Provisioning: ${target_hostname}"
green "=========================================="

if [ "$dry_run" -eq 1 ]; then
	yellow "DRY-RUN MODE: No changes will be made."
fi

blue "Configuration:"
blue "  Hostname:      ${target_hostname}"
blue "  Destination:   ${target_destination:-N/A}"
blue "  Disk layout:   ${disk_layout}"
blue "  Primary disk:  ${disk:-N/A}"
blue "  Secondary:     ${disk2:-N/A}"
blue "  User:          ${target_user}"
blue "  SSH port:      ${ssh_port}"
blue "  SSH key:       ${ssh_key:-agent}"
blue "  Impermanence:  ${persist_dir:-disabled}"
blue "  Builder:       ${builder:-default}"
blue "  Phases:        ${phases}$([ "$migrate_mode" -eq 1 ] && echo ' (migrate)')$([ "$target_installer" -eq 1 ] && echo ' (installer mode)')"
echo

# Phase 0: Scaffold host config
if [ "$run_scaffold" -eq 1 ]; then
	scaffold_host
fi

# Phase 1: Prepare secrets
if [ "$run_prepare" -eq 1 ]; then
	prepare_secrets
fi

# Phase 1-M: Migrate mode — verify SSH key exists in sops
if [ "$migrate_mode" -eq 1 ]; then
	migrate_extract_ssh_key
fi

# Phase 2: Install system
if [ "$run_install" -eq 1 ]; then
	install_system
fi

# Phase 3: Deploy full config
if [ "$run_deploy" -eq 1 ]; then
	deploy_config
fi

green "=========================================="
green "Provisioning complete for ${target_hostname}!"
green "=========================================="
