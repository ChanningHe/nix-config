#!/usr/bin/env bash
set -eo pipefail

### UX helpers

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

function blue() {
	echo -e "\x1B[34m[*] $1 \x1B[0m"
	if [ -n "${2-}" ]; then
		echo -e "\x1B[34m[*] $($2) \x1B[0m"
	fi
}

function yellow() {
	echo -e "\x1B[33m[*] $1 \x1B[0m"
	if [ -n "${2-}" ]; then
		echo -e "\x1B[33m[*] $($2) \x1B[0m"
	fi
}

# Ask yes or no, with yes being the default
function yes_or_no() {
	echo -en "\x1B[34m[?] $* [y/n] (default: y): \x1B[0m"
	while true; do
		read -rp "" yn
		yn=${yn:-y}
		case $yn in
		[Yy]*) return 0 ;;
		[Nn]*) return 1 ;;
		esac
	done
}

# Ask yes or no, with no being the default
function no_or_yes() {
	echo -en "\x1B[34m[?] $* [y/n] (default: n): \x1B[0m"
	while true; do
		read -rp "" yn
		yn=${yn:-n}
		case $yn in
		[Yy]*) return 0 ;;
		[Nn]*) return 1 ;;
		esac
	done
}

### SOPS helpers
nix_secrets_dir=${NIX_SECRETS_DIR:-"$(dirname "${BASH_SOURCE[0]}")/../../nix-secrets"}
SOPS_FILE="${nix_secrets_dir}/.sops.yaml"

# Updates the .sops.yaml file with a new host or user age key.
function sops_update_age_key() {
	field="$1"
	keyname="$2"
	key="$3"

	if [ ! "$field" == "hosts" ] && [ ! "$field" == "users" ]; then
		red "Invalid field passed to sops_update_age_key. Must be either 'hosts' or 'users'."
		exit 1
	fi

	if [[ -n $(yq ".keys.${field}[] | select(anchor == \"$keyname\")" "${SOPS_FILE}") ]]; then
		green "Updating existing ${keyname} key"
		yq -i "(.keys.${field}[] | select(anchor == \"$keyname\")) = \"$key\"" "$SOPS_FILE"
	else
		green "Adding new ${keyname} key"
		yq -i ".keys.$field += [\"$key\"] | .keys.${field}[-1] anchor = \"$keyname\"" "$SOPS_FILE"
	fi
}

# Adds the host alias to the shared.yaml creation rules
function sops_add_shared_creation_rules() {
	h="\"$2\"" # quoted hostname for yaml

	# FIX: match actual path_regex which includes "secrets/" prefix
	shared_selector='.creation_rules[] | select(.path_regex | test("shared"))'
	if [[ -n $(yq "$shared_selector" "${SOPS_FILE}") ]]; then
		if [[ -z $(yq "$shared_selector.key_groups[].age[] | select(alias == $h)" "${SOPS_FILE}") ]]; then
			green "Adding $h to shared.yaml rule"
			yq -i "($shared_selector).key_groups[].age += [$h]" "$SOPS_FILE"
			yq -i "($shared_selector).key_groups[].age[-1] alias = $h" "$SOPS_FILE"
		else
			green "Host $h already in shared.yaml rule"
		fi
	else
		red "shared.yaml rule not found in ${SOPS_FILE}"
	fi
}

# Adds a new host.yaml creation rule with all existing user keys + host key.
# Uses direct text generation instead of yq alias manipulation (which is unreliable).
# args: user, hostname
function sops_add_host_creation_rules() {
	local host="$2"

	# Check if rule already exists (use grep for reliable matching)
	if grep -q "secrets/${host}" "${SOPS_FILE}" 2>/dev/null; then
		green "Host creation rule for ${host} already exists"
		return
	fi

	green "Adding new host creation rule for ${host}"

	# Collect all user anchor names from keys.users
	local user_anchors
	user_anchors=$(yq '.keys.users[] | anchor' "${SOPS_FILE}")

	# Build YAML block matching exact format of existing entries
	# Indentation: 2 for rule, 4 for key_groups, 6 for age list header, 10 for age entries
	{
		echo "  - path_regex: secrets/${host}\\.yaml\$"
		echo "    key_groups:"
		echo "      - age:"
		while IFS= read -r anchor_name; do
			[ -z "$anchor_name" ] && continue
			echo "          - *${anchor_name}"
		done <<<"$user_anchors"
		echo "          - *${host}"
	} >>"$SOPS_FILE"

	green "Created rule: secrets/${host}.yaml"
}

# Adds the user and host to the shared.yaml and host.yaml creation rules
function sops_add_creation_rules() {
	user="$1"
	host="$2"

	sops_add_shared_creation_rules "$user" "$host"
	sops_add_host_creation_rules "$user" "$host"
}

age_secret_key=""
# Generate a user age key, update the .sops.yaml entries, and return the key in age_secret_key
# args: user, hostname
function sops_generate_user_age_key() {
	target_user="$1"
	target_hostname="$2"
	key_name="${target_user}_${target_hostname}"
	green "Age key does not exist. Generating."
	user_age_key=$(age-keygen)
	readarray -t entries <<<"$user_age_key"
	age_secret_key=${entries[2]}
	public_key=$(echo "${entries[1]}" | rg key: | cut -f2 -d: | xargs)
	green "Generated age key for ${key_name}"
	# Place the anchors into .sops.yaml so other commands can reference them
	sops_update_age_key "users" "$key_name" "$public_key"
	sops_add_creation_rules "${target_user}" "${target_hostname}"

	# "return" key so it can be used by caller
	export age_secret_key
}

function sops_setup_user_age_key() {
	target_user="$1"
	target_hostname="$2"

	# FIX: use secrets/ directory to match creation_rules path_regex (not sops/)
	secret_file="${nix_secrets_dir}/secrets/${target_hostname}.yaml"
	config="${nix_secrets_dir}/.sops.yaml"
	# If the secret file doesn't exist, create it with a new user age key
	if [ ! -f "$secret_file" ]; then
		green "Host secret file does not exist. Creating $secret_file"
		sops_generate_user_age_key "${target_user}" "${target_hostname}"
		mkdir -p "$(dirname "$secret_file")"
		echo "{}" >"$secret_file"
		sops --config "$config" -e "$secret_file" >"$secret_file.enc"
		mv "$secret_file.enc" "$secret_file"
	fi
	if ! sops --config "$config" -d --extract '["keys"]["age"]' "$secret_file" >/dev/null 2>&1; then
		if [ -z "$age_secret_key" ]; then
			sops_generate_user_age_key "${target_user}" "${target_hostname}"
		fi
		# shellcheck disable=SC2116,SC2086
		sops --config "$config" --set "$(echo '["keys"]["age"] "'$age_secret_key'"')" "$secret_file"
	else
		green "Age key already exists for ${target_hostname}"
	fi
}
