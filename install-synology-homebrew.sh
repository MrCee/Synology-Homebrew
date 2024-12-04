#!/bin/bash

# File: install-synology-homebrew.sh

# Enable strict error handling and debugging
DEBUG=0
[[ $DEBUG -eq 1 ]] && echo "DEBUG mode on with strict -euo pipefail error handling" && set -euo pipefail
[[ $DEBUG -eq 1 ]] && set -x  # Enable debug mode if DEBUG=1

# Determine script directory
SCRIPT_PATH=$(realpath "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
cd "$SCRIPT_DIR" || { echo "Failed to change directory to $SCRIPT_DIR" >&2; exit 1; }
echo "Working directory: $(pwd)"

# Source shared functions
source "./functions.sh"

# Initialize environment variables
func_initialize_env_vars

# Save original stty settings and disable echoctl
orig_stty=$(stty -g)
export orig_stty
stty -echoctl

# Display environment variables
echo "DARWIN: $DARWIN"
echo "HOMEBREW_PATH: $HOMEBREW_PATH"
echo "DEFAULT_GROUP: $DEFAULT_GROUP"

# Set traps for cleanup
trap 'code=$?; func_cleanup_exit $code' EXIT
trap 'func_cleanup_exit 130' INT TERM HUP QUIT ABRT ALRM PIPE

# Setup sudoers file
func_sudoers

# Verify sudoers setup
if [[ "${SUDOERS_SETUP_DONE:-0}" -ne 1 ]]; then
    echo "Sudoers setup was not completed successfully. Exiting." >&2
    exit 1
fi

[[ $DEBUG -eq 1 ]] && echo "Debug: SUDOERS_FILE is set to '$SUDOERS_FILE'"

# Prevent running as root
if [[ "$EUID" -eq 0 ]]; then
    echo "This script should not be run as root. Run it as a regular user." >&2
    exit 1
fi

# Define package lists and install packages
func_define_package_lists

for pkg in "${packages[@]}"; do
    func_install_if_missing "$pkg"
done

# Upgrade packages
func_upgrade_packages

# Ensure config.yaml exists
CONFIG_YAML="${1:-./config.yaml}"
if [[ ! -f "$CONFIG_YAML" ]]; then
    echo "config.yaml not found in the current directory." >&2
    exit 1
fi

# YAML Cleanup
func_sed 's/([^\\])\\([^\\"])/\1\\\\\2/g' "$CONFIG_YAML"
func_sed 's/(^.*:[[:space:]]"[^\"]*)("[^"]*)(".*"$)/\1\\\2\\\3/g' "$CONFIG_YAML"

# Validate YAML
yq eval '.' "$CONFIG_YAML" > /dev/null 2>&1
if [[ $? -ne 0 ]]; then
    printf "Error: The YAML file '%s' is invalid.\n" "$CONFIG_YAML" >&2
    exit 1
else
    printf "The YAML file '%s' is valid.\n" "$CONFIG_YAML"
fi

echo "--------------------------PATH SET-------------------------------"
echo "$PATH"
echo "-----------------------------------------------------------------"


# Process additional Homebrew packages from config.yaml
process_additional_packages "$CONFIG_YAML"


# Call zsh_config.sh and pass config.yaml
./zsh_config.sh "$CONFIG_YAML"

# Display summary of actions
display_summary

echo "Script completed successfully. You will now be transported to ZSH!!!"
exec zsh --login

