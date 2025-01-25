#!/usr/bin/env bash
set -eo pipefail

# Helpers library
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

# User variables
target_hostname=""
target_destination=""
target_user=${BOOTSTRAP_USER-$(whoami)} # Set BOOTSTRAP_ defaults in your shell.nix
ssh_port=${BOOTSTRAP_SSH_PORT-22}
ssh_key=${BOOTSTRAP_SSH_KEY-}
persist_dir=""
luks_secondary_drive_labels=""

# Create a temp directory for generated host keys
temp=$(mktemp -d)

# Cleanup temporary directory on exit
function cleanup() {
	rm -rf "$temp"
}
trap cleanup exit

# Copy data to the target machine
function sync() {
	# $1 = user, $2 = source, $3 = destination
	rsync -av --filter=':- .gitignore' -e "ssh -l $1 -oport=${ssh_port}" "$2" "$1@${target_destination}:"
}

# Usage function
function help_and_exit() {
	echo
	echo "Remotely installs NixOS on a target machine using this nix-config."
	echo
	echo "USAGE: $0 -n <target_hostname> -d <target_destination> -k <ssh_key> [OPTIONS]"
	echo
	echo "ARGS:"
	echo "  -n <target_hostname>                    specify target_hostname of the target host to deploy the nixos config on."
	echo "  -d <target_destination>                 specify ip or domain to the target host."
	echo "  -k <ssh_key>                            specify the full path to the ssh_key you'll use for remote access to the"
	echo "                                          target during install process."
	echo "                                          Example: -k /home/${target_user}/.ssh/my_ssh_key"
	echo
	echo "OPTIONS:"
	echo "  -u <target_user>                        specify target_user with sudo access. nix-config will be cloned to their home."
	echo "                                          Default='${target_user}'."
	echo "  --port <ssh_port>                       specify the ssh port to use for remote access. Default=${ssh_port}."
	echo '  --luks-secondary-drive-labels <drives>  specify the luks device names (as declared with "disko.devices.disk.*.content.luks.name" in host/common/disks/*.nix) separated by commas.'
	echo '                                          Example: --luks-secondary-drive-labels "cryptprimary,cryptextra"'
	echo "  --impermanence                          Use this flag if the target machine has impermanence enabled. WARNING: Assumes /persist path."
	echo "  --debug                                 Enable debug mode."
	echo "  -h | --help                             Print this help."
	exit 0
}

# Handle command-line arguments
while [[ $# -gt 0 ]]; do
	case "$1" in
	-n)
		shift
		target_hostname=$1
		;;
	-d)
		shift
		target_destination=$1
		;;
	-u)
		shift
		target_user=$1
		;;
	-k)
		shift
		ssh_key=$1
		;;
	--luks-secondary-drive-labels)
		shift
		luks_secondary_drive_labels=$1
		;;
	--port)
		shift
		ssh_port=$1
		;;
	--temp-override)
		shift
		temp=$1
		;;
	--impermanence)
		persist_dir="/persist"
		;;
	--debug)
		set -x
		;;
	-h | --help) help_and_exit ;;
	*)
		red "ERROR: Invalid option detected."
		help_and_exit
		;;
	esac
	shift
done

if [ -z "$target_hostname" ] || [ -z "$target_destination" ] || [ -z "$ssh_key" ]; then
	red "ERROR: -n, -d, and -k are all required"
	echo
	help_and_exit
fi

# SSH commands
ssh_cmd="ssh -oControlMaster=no -oport=${ssh_port} -oForwardAgent=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $ssh_key -t $target_user@$target_destination"
# shellcheck disable=SC2001
ssh_root_cmd=$(echo "$ssh_cmd" | sed "s|${target_user}@|root@|") # uses @ in the sed switch to avoid it triggering on the $ssh_key value
scp_cmd="scp -oControlMaster=no -oport=${ssh_port} -o StrictHostKeyChecking=no -i $ssh_key"

git_root=$(git rev-parse --show-toplevel)

# Setup minimal environment for nixos-anywhere and run it
function nixos_anywhere() {
	# Clear the known keys, since they should be newly generated for the iso
	green "Wiping known_hosts of $target_destination"
	sed -i "/$target_hostname/d; /$target_destination/d" ~/.ssh/known_hosts

	green "Installing NixOS on remote host $target_hostname at $target_destination"

	###
	# nixos-anywhere extra-files generation
	###
	green "Preparing a new ssh_host_ed25519_key pair for $target_hostname."
	# Create the directory where sshd expects to find the host keys
	install -d -m755 "$temp/$persist_dir/etc/ssh"

	# Generate host ssh key pair without a passphrase
	ssh-keygen -t ed25519 -f "$temp/$persist_dir/etc/ssh/ssh_host_ed25519_key" -C "$target_user"@"$target_hostname" -N ""

	# Set the correct permissions so sshd will accept the key
	chmod 600 "$temp/$persist_dir/etc/ssh/ssh_host_ed25519_key"

	green "Adding ssh host fingerprint at $target_destination to ~/.ssh/known_hosts"
	# This will fail if we already know the host, but that's fine
	ssh-keyscan -p "$ssh_port" "$target_destination" | grep -v '^#' >>~/.ssh/known_hosts || true

	###
	# nixos-anywhere installation
	###
	cd nixos-installer
	# when using luks, disko expects a passphrase on /tmp/disko-password, so we set it for now and will update the passphrase later
	temp_luks_passphrase="passphrase"
	if no_or_yes "Manually set luks encryption passphrase? (Default: \"$temp_luks_passphrase\")"; then
		blue "Enter your luks encryption passphrase:"
		read -rs luks_passphrase
		$ssh_root_cmd "/bin/sh -c 'echo $luks_passphrase > /tmp/disko-password'"
	else
		green "Using '$temp_luks_passphrase' as the luks encryption passphrase. Change after installation."
		$ssh_root_cmd "/bin/sh -c 'echo $temp_luks_passphrase > /tmp/disko-password'"
	fi

	# If you are rebuilding a machine without any hardware changes, this is likely unneeded or even possibly disruptive
	if yes_or_no "Generate a new hardware config for this host?"; then
		green "Generating hardware-configuration.nix on $target_hostname and adding it to the local nix-config."
		$ssh_root_cmd "nixos-generate-config --no-filesystems --root /mnt"
		$scp_cmd root@"$target_destination":/mnt/etc/nixos/hardware-configuration.nix "${git_root}"/hosts/nixos/"$target_hostname"/hardware-configuration.nix
	fi

	# --extra-files here picks up the ssh host key we generated earlier and puts it onto the target machine
	SHELL=/bin/sh nix run github:nix-community/nixos-anywhere -- --ssh-port "$ssh_port" --post-kexec-ssh-port "$ssh_port" --extra-files "$temp" --flake .#"$target_hostname" root@"$target_destination"

	if ! yes_or_no "Has your system restarted and are you ready to continue? (no exits)"; then
		exit 0
	fi

	green "Adding $target_destination's ssh host fingerprint to ~/.ssh/known_hosts"
	ssh-keyscan -p "$ssh_port" "$target_destination" | grep -v '^#' >>~/.ssh/known_hosts || true

	if [ -n "$persist_dir" ]; then
		$ssh_root_cmd "cp /etc/machine-id $persist_dir/etc/machine-id || true"
		$ssh_root_cmd "cp -R /etc/ssh/ $persist_dir/etc/ssh/ || true"
	fi
	cd - >/dev/null
}

function generate_host_age_key() {
	green "Generating an age key based on the new ssh_host_ed25519_key"

	# Get the SSH key
	target_key=$(ssh-keyscan -p "$ssh_port" -t ssh-ed25519 "$target_destination" 2>&1 | grep ssh-ed25519 | cut -f2- -d" ") || {
		red "Failed to get ssh key. Host down or maybe SSH port now changed?"
		exit 1
	}

	host_age_key=$(nix shell nixpkgs#ssh-to-age.out -c sh -c "echo $target_key | ssh-to-age")

	if grep -qv '^age1' <<<"$host_age_key"; then
		red "The result from generated age key does not match the expected format."
		yellow "Result: $host_age_key"
		yellow "Expected format: age10000000000000000000000000000000000000000000000000000000000"
		exit 1
	fi

	green "Updating nix-secrets/.sops.yaml"
	sops_update_age_key "hosts" "$target_hostname" "$host_age_key"
}

age_secret_key=""
# Generate a user age key
function generate_user_age_key() {
	green "Age key does not exist. Generating."
	user_age_key=$(nix shell nixpkgs#age -c "age-keygen")
	readarray -t entries <<<"$user_age_key"
	age_secret_key=${entries[2]}
	public_key=$(echo "${entries[1]}" | rg key: | cut -f2 -d: | xargs)
	key_name="${target_user}_${target_hostname}"
	green "Generated age key for ${key_name}"
	# Place the anchors into .sops.yaml so other commands can reference them
	sops_update_age_key "users" "$key_name" "$public_key"
	sops_add_creation_rules "${target_user}" "${target_hostname}"
}

function generate_user_age_key_and_file() {
	# FIXME(starter-repo): remove old secrets.yaml line once starter repo is completed
	#secret_file="${git_root}"/../nix-secrets/secrets.yaml
	secret_file="${git_root}"/../nix-secrets/sops/${target_hostname}.yaml
	config="${git_root}"/../nix-secrets/.sops.yaml
	# If the secret file doesn't exist, it means we're generating a new user key as well
	if [ ! -f "$secret_file" ]; then
		green "Host secret file does not exist. Creating $secret_file"
		generate_user_age_key
		echo "{}" >"$secret_file"
		sops --config "$config" -e "$secret_file" >"$secret_file.enc"
		mv "$secret_file.enc" "$secret_file"
	fi
	if ! sops --config "$config" -d --extract '["keys]["age"]' "$secret_file" >/dev/null 2>&1; then
		if [ -z "$age_secret_key" ]; then
			generate_user_age_key
		fi
		echo "Secret key $age_secret_key"
		# shellcheck disable=SC2116,SC2086
		sops --config "$config" --set "$(echo '["keys"]["age"] "'$age_secret_key'"')" "$secret_file"
	else
		green "Age key already exists for ${target_hostname}"
	fi
}

function setup_luks_secondary_drive_decryption() {
	green "Generating /luks-secondary-unlock.key"
	local key=${persist_dir}/luks-secondary-unlock.key
	$ssh_root_cmd "/bin/sh -c 'dd bs=512 count=4 if=/dev/random of=$key iflag=fullblock && chmod 400 $key'"

	green "Cryptsetup luksAddKey will now be used to add /luks-secondary-unlock.key for the specified secondary drive names."
	readarray -td, drivenames <<<"$luks_secondary_drive_labels"
	for name in "${drivenames[@]}"; do
		device_path=$($ssh_root_cmd -q "/bin/sh -c 'cryptsetup status \"$name\" | awk \'/device:/ {print \$2}\''")
		$ssh_root_cmd "/bin/sh -c 'echo \"$luks_passphrase\" | cryptsetup luksAddKey $device_path /luks-secondary-unlock.key'"
	done
}

# Validate required options
# FIXME(bootstrap): The ssh key and destination aren't required if only rekeying, so could be moved into specific sections?
if [ -z "${target_hostname}" ] || [ -z "${target_destination}" ] || [ -z "${ssh_key}" ]; then
	red "ERROR: -n, -d, and -k are all required"
	echo
	help_and_exit
fi

if yes_or_no "Run nixos-anywhere installation?"; then
	nixos_anywhere
fi

if yes_or_no "Generate host (ssh-based) age key?"; then
	generate_host_age_key
	updated_age_keys=1
fi

if yes_or_no "Generate user age key?"; then
	# This may end up creating the host.yaml file, so add creation rules in advance
	generate_user_age_key_and_file
	updated_age_keys=1
fi

if [[ $updated_age_keys == 1 ]]; then
	# If the age generation commands added previously unseen keys (and associated anchors) we want to add those
	# to some creation rules, namely <host>.yaml and shared.yaml
	sops_add_creation_rules "${target_user}" "${target_hostname}"
	# Since we may update the sops.yaml file twice above, only rekey once at the end
	just rekey
	green "Updating flake input to pick up new .sops.yaml"
	nix flake update nix-secrets
fi

green "NOTE: If this is the first time running this script on $target_hostname, the next step is required to continue"
if yes_or_no "Add ssh host fingerprints for git{lab,hub}?"; then
	if [ "$target_user" == "root" ]; then
		home_path="/root"
	else
		home_path="/home/$target_user"
	fi
	green "Adding ssh host fingerprints for git{lab,hub}"
	$ssh_cmd "mkdir -p $home_path/.ssh/; ssh-keyscan -t ssh-ed25519 gitlab.com github.com 2>/dev/null | grep -v '^#' >>$home_path/.ssh/known_hosts"
fi

if yes_or_no "Do you want to copy your full nix-config and nix-secrets to $target_hostname?"; then
	green "Adding ssh host fingerprint at $target_destination to ~/.ssh/known_hosts"
	ssh-keyscan -p "$ssh_port" "$target_destination" 2>/dev/null | grep -v '^#' >>~/.ssh/known_hosts || true
	green "Copying full nix-config to $target_hostname"
	sync "$target_user" "${git_root}"/../nix-config
	green "Copying full nix-secrets to $target_hostname"
	sync "$target_user" "${git_root}"/../nix-secrets

	# FIXME(bootstrap): Add some sort of key access from the target to download the config (if it's a cloud system)
	if yes_or_no "Do you want to rebuild immediately? (requires yubikey-agent)"; then
		green "Rebuilding nix-config on $target_hostname"
		$ssh_cmd "cd nix-config && sudo nixos-rebuild --impure --show-trace --flake .#$target_hostname switch"
	fi
else
	echo
	green "NixOS was successfully installed!"
	echo "Post-install config build instructions:"
	echo "To copy nix-config from this machine to the $target_hostname, run the following command"
	echo "just sync $target_user $target_destination"
	echo "To rebuild, sign into $target_hostname and run the following command"
	echo "cd nix-config"
	echo "sudo nixos-rebuild --show-trace --flake .#$target_hostname switch"
	echo
fi

if yes_or_no "Do you want to commit and push the nix-config, which includes the hardware-configuration.nix for $target_hostname?"; then
	(pre-commit run --all-files 2>/dev/null || true) &&
		git add "$git_root/hosts/$target_hostname/hardware-configuration.nix" && (git commit -m "feat: hardware-configuration.nix for $target_hostname" || true) && git push
fi

green "Success!"
