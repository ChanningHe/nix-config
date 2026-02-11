#!/usr/bin/env bash
set -euo pipefail

# Scaffold a new NixOS host: create basic nix-config and nix-secrets entries.
# Does NOT handle secrets/, .sops.yaml, or hardware-configuration.nix.

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

###############################################################################
# Paths
###############################################################################

git_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
nix_secrets_dir="${NIX_SECRETS_DIR:-"${git_root}/../nix-secrets"}"
host_template="${git_root}/hosts/host-template.nix.placeholder"
home_template="${git_root}/home/channinghe/home-template.nix.placeholder"
network_nix="${nix_secrets_dir}/nix/network.nix"

###############################################################################
# Usage
###############################################################################

function help_and_exit() {
	echo
	echo "Scaffold a new NixOS host with minimal config."
	echo
	echo "USAGE: $0 -n <hostname> [OPTIONS]"
	echo
	echo "REQUIRED:"
	echo "  -n, --hostname <name>       New host name"
	echo
	echo "NETWORK:"
	echo "  --ip4 <address>             IPv4 address (e.g. 10.1.10.100)"
	echo "  --gateway4 <address>        IPv4 gateway (e.g. 10.1.10.1)"
	echo "  --dns <address>             DNS server (default: 10.1.10.2)"
	echo "  --interface <name>          Network interface (e.g. enp3s0)"
	echo
	echo "OTHER:"
	echo "  --host-id <hex>             8-char hex hostId (auto-generated if omitted)"
	echo "  -h, --help                  Show this help"
	echo
	exit 0
}

###############################################################################
# Defaults
###############################################################################

hostname=""
ip4=""
gateway4=""
dns=""
interface=""
host_id=""

###############################################################################
# Parse arguments
###############################################################################

while [[ $# -gt 0 ]]; do
	case "$1" in
	-n | --hostname)
		hostname="$2"
		shift 2
		;;
	--ip4)
		ip4="$2"
		shift 2
		;;
	--gateway4)
		gateway4="$2"
		shift 2
		;;
	--dns)
		dns="$2"
		shift 2
		;;
	--interface)
		interface="$2"
		shift 2
		;;
	--host-id)
		host_id="$2"
		shift 2
		;;
	-h | --help)
		help_and_exit
		;;
	*)
		red "Unknown option: $1"
		help_and_exit
		;;
	esac
done

###############################################################################
# Validate templates exist
###############################################################################

if [[ ! -f $host_template ]]; then
	red "Host template not found: ${host_template}"
	exit 1
fi

if [[ ! -f $home_template ]]; then
	red "Home template not found: ${home_template}"
	exit 1
fi

###############################################################################
# Interactive prompts for missing values
###############################################################################

if [[ -z $hostname ]]; then
	echo -en "\x1B[34m[?] Hostname: \x1B[0m"
	read -r hostname
fi

if [[ -z $hostname ]]; then
	red "Hostname is required."
	exit 1
fi

# Validate: host directory and home file must not exist
host_dir="${git_root}/hosts/nixos/${hostname}"
home_file="${git_root}/home/channinghe/${hostname}.nix"

if [[ -d $host_dir ]]; then
	red "Host directory already exists: ${host_dir}"
	exit 1
fi

if [[ -f $home_file ]]; then
	red "Home config already exists: ${home_file}"
	exit 1
fi

if [[ -z $ip4 ]]; then
	echo -en "\x1B[34m[?] IPv4 address (e.g. 10.1.10.100): \x1B[0m"
	read -r ip4
fi

if [[ -z $ip4 ]]; then
	red "IPv4 address is required."
	exit 1
fi

if [[ -z $gateway4 ]]; then
	echo -en "\x1B[34m[?] IPv4 gateway (e.g. 10.1.10.1): \x1B[0m"
	read -r gateway4
fi

if [[ -z $gateway4 ]]; then
	red "IPv4 gateway is required."
	exit 1
fi

if [[ -z $dns ]]; then
	echo -en "\x1B[34m[?] DNS server (default: 10.1.10.2): \x1B[0m"
	read -r dns
	dns="${dns:-10.1.10.2}"
fi

if [[ -z $interface ]]; then
	echo -en "\x1B[34m[?] Network interface name (e.g. enp3s0): \x1B[0m"
	read -r interface
fi

if [[ -z $interface ]]; then
	red "Network interface is required."
	exit 1
fi

# Generate hostId if not provided
if [[ -z $host_id ]]; then
	host_id=$(head -c4 /dev/urandom | od -A none -t x4 | xargs)
	blue "Generated hostId: ${host_id}"
	echo -en "\x1B[34m[?] Press Enter to accept, or type a custom hostId: \x1B[0m"
	read -r custom_id
	if [[ -n $custom_id ]]; then
		host_id="$custom_id"
	fi
fi

###############################################################################
# Confirmation
###############################################################################

echo
blue "====== New Host Summary ======"
echo "  Hostname:   ${hostname}"
echo "  IPv4:       ${ip4}"
echo "  Gateway:    ${gateway4}"
echo "  DNS:        ${dns}"
echo "  Interface:  ${interface}"
echo "  Host ID:    ${host_id}"
echo
echo "  Will create:"
echo "    ${host_dir}/default.nix"
echo "    ${home_file}"
echo "    Add entry to ${network_nix}"
echo

if ! yes_or_no "Proceed?"; then
	yellow "Aborted."
	exit 0
fi

###############################################################################
# 1. Create host config: hosts/nixos/<hostname>/default.nix
###############################################################################

green "Creating host config..."
mkdir -p "${host_dir}"

# Copy template and substitute FIXME placeholders
sed \
	-e "s/hostName = \"foo\"/hostName = \"${hostname}\"/" \
	-e "s/hostId = \"xxxxx\"/hostId = \"${host_id}\"/" \
	-e "s/matchConfig\.Name = \"xxxxx\"/matchConfig.Name = \"${interface}\"/" \
	-e '/# \!\!\!\[FIXME\]\!\!\!/d' \
	"${host_template}" >"${host_dir}/default.nix"

green "Created ${host_dir}/default.nix"

###############################################################################
# 2. Create home-manager config: home/channinghe/<hostname>.nix
###############################################################################

cp "${home_template}" "${home_file}"
green "Created ${home_file}"

###############################################################################
# 3. Inject network entry into nix-secrets/nix/network.nix
###############################################################################

if [[ ! -f $network_nix ]]; then
	red "nix-secrets network.nix not found: ${network_nix}"
	yellow "Skipping network injection. Add the entry manually."
else
	# Check if host already exists in network.nix
	if grep -q "^[[:space:]]*${hostname} = {" "$network_nix"; then
		yellow "Host '${hostname}' already exists in network.nix, skipping injection."
	else
		# Insert new host block before "# Other hosts" marker using awk + env vars
		tmp_file=$(mktemp)
		NH_HOSTNAME="$hostname" NH_IP4="$ip4" NH_GATEWAY4="$gateway4" NH_DNS="$dns" \
			awk '/# Other hosts/ {
				printf "      %s = {\n", ENVIRON["NH_HOSTNAME"]
				printf "        ip4 = \"%s\";\n", ENVIRON["NH_IP4"]
				printf "        gateway4 = \"%s\";\n", ENVIRON["NH_GATEWAY4"]
				printf "        dns = [ \"%s\" ];\n", ENVIRON["NH_DNS"]
				printf "      };\n"
			}
			{ print }' \
			"${network_nix}" >"${tmp_file}"
		mv "${tmp_file}" "${network_nix}"
		green "Added network entry to ${network_nix}"
	fi
fi

###############################################################################
# Done
###############################################################################

echo
green "====== Host scaffold complete ======"
echo
yellow "Next steps:"
echo "  1. Generate hardware-configuration.nix on the target machine:"
echo "     nixos-generate-config --show-hardware-config > hosts/nixos/${hostname}/hardware-configuration.nix"
echo "  2. Review and customize hosts/nixos/${hostname}/default.nix"
echo "  3. Review and customize home/channinghe/${hostname}.nix"
echo "  4. After first boot, add host SSH key to nix-secrets/.sops.yaml:"
echo "     nix-shell -p ssh-to-age --run 'cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age'"
echo "  5. Run: just rebuild"
