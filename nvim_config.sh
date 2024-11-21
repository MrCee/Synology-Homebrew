#!/bin/bash

# Enable strict error handling
set -euo pipefail

# Define icons for better readability
INFO="ℹ️"
SUCCESS="✅"
WARNING="⚠️"
ERROR="❌"
TOOLS="🛠️"
REMOVE="🗑️"
REVOCATION="🔒"

printf "${SUCCESS} Successfully called %s\n" "$(basename "$0")"

# Source the functions file
source "./functions.sh"

# Initialize environment variables
func_initialize_env_vars
echo "${INFO} DARWIN: $DARWIN"
echo "${INFO} HOMEBREW_PATH: $HOMEBREW_PATH"
echo "${INFO} DEFAULT_GROUP: $DEFAULT_GROUP"

# Assign the first argument to temp_file, default to empty if not provided
temp_file=${1:-}

# Determine if the script is called by the main script or run directly
if [[ -n "$temp_file" && -f "$temp_file" ]]; then
    echo "${INFO} Script is being called by the main script with temp file: $temp_file"
    CALLED_BY_MAIN=1
else
    echo "${INFO} Script is being run directly by the user."
    CALLED_BY_MAIN=0
fi

# Main logic of nvim_config.sh
echo "${TOOLS} Running Neovim configuration tasks..."

# Validate and read YAML from the temporary file or config.yaml
if [[ "$CALLED_BY_MAIN" -eq 1 ]]; then
    if ! CONFIG_YAML=$(<"$temp_file"); then
        printf "${ERROR} Failed to read YAML file at %s\n" "$temp_file" >&2
        exit 1
    fi
    echo "${INFO} Tempfile parsed correctly: $temp_file"
else
    CONFIG_YAML_PATH="./config.yaml"

    # Ensure config.yaml exists
    if [[ ! -f "$CONFIG_YAML_PATH" ]]; then
        printf "${ERROR} config.yaml not found in this directory\n" >&2
        exit 1
    fi

    if ! CONFIG_YAML=$(<"$CONFIG_YAML_PATH"); then
        printf "${ERROR} Failed to read YAML file at %s\n" "$CONFIG_YAML_PATH" >&2
        exit 1
    fi

    echo -e "-----------------------------------------------------------------\n"
    read -p "Would you like to check and install Neovim dependencies? (y/n): " answer
    if [[ "$answer" == "y" ]]; then
        CONFIG_YAML=$(printf '%s\n' "$CONFIG_YAML" | yq e '.packages.neovim.install = "true"')
    fi

    read -p "Would you like to check and install kickstart.nvim? (y/n): " answer
    if [[ "$answer" == "y" ]]; then
        CONFIG_YAML=$(printf '%s\n' "$CONFIG_YAML" | yq e '.plugins."kickstart.nvim".install = "true"')
    fi
fi

# Function to update the install status in the YAML
update_install_status() {
    local plugin="$1"
    CONFIG_YAML=$(printf '%s\n' "$CONFIG_YAML" | yq e ".plugins[\"$plugin\"].install = \"handled\"" -)
}

# Install kickstart.nvim if install is true in config.yaml
if [[ $(printf '%s\n' "$CONFIG_YAML" | yq eval -r '.plugins."kickstart.nvim".install') == "true" ]]; then
    kickstart_dir=$(printf '%s\n' "$CONFIG_YAML" | yq eval -r '.plugins."kickstart.nvim".directory')
    eval kickstart_dir="$kickstart_dir"

    if [[ ! -d "$kickstart_dir" ]]; then
        echo "${TOOLS} Installing kickstart.nvim..."
        git clone "$(printf '%s\n' "$CONFIG_YAML" | yq eval -r '.plugins."kickstart.nvim".url')" "$kickstart_dir"
        update_install_status "kickstart.nvim"
    else
        update_install_status "kickstart.nvim"
        echo "${SUCCESS} kickstart.nvim is already installed."
    fi
fi

# Additional configuration and logic here (omitted for brevity)...

# Perform cleanup only if run directly
if [[ "$CALLED_BY_MAIN" -eq 0 ]]; then
    echo "${REMOVE} Performing cleanup since script was run directly."
    func_cleanup_exit 0
else
    echo "${INFO} Skipping cleanup because the main script is managing it."
fi

