#!/bin/bash

# Ensure DEBUG is set to 0 if unset or null
: "${DEBUG:=0}"
[[ $DEBUG == 1 ]] && echo "DEBUG mode on with strict -euo pipefail error handling" && set -euo pipefail

SCRIPT_PATH=$(realpath "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")

# Change to the script directory
cd "$SCRIPT_DIR" || { echo "Failed to change directory to $SCRIPT_DIR" >&2; exit 1; }
echo "Working directory: $(pwd)"


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
echo "${INFO} USERNAME: $USERNAME"
echo "${INFO} USERGROUP: $USERGROUP"
echo "${INFO} ROOTGROUP: $ROOTGROUP"

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

# Main logic of install-neovim.sh
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
        CONFIG_YAML=$(printf '%s\n' "$CONFIG_YAML" | yq e '.packages.neovim.action = "install"')
    else
        CONFIG_YAML=$(printf '%s\n' "$CONFIG_YAML" | yq e '.packages.neovim.action = "skip"')
    fi

    read -p "Would you like to check and install kickstart.nvim? (y/n): " answer
    if [[ "$answer" == "y" ]]; then
        CONFIG_YAML=$(printf '%s\n' "$CONFIG_YAML" | yq e '.plugins."kickstart.nvim".action = "install"')
    else
        CONFIG_YAML=$(printf '%s\n' "$CONFIG_YAML" | yq e '.plugins."kickstart.nvim".action = "skip"')

    fi
 func_sudoers
fi

# Function to update the action status in the YAML
update_action_status() {
    local plugin="$1"
    CONFIG_YAML=$(printf '%s\n' "$CONFIG_YAML" | yq e ".plugins[\"$plugin\"].action = \"handled\"" -)
}

# Install kickstart.nvim based on the action in config.yaml
kickstart_action=$(printf '%s\n' "$CONFIG_YAML" | yq eval -r '.plugins."kickstart.nvim".action')

if [[ "$kickstart_action" == "install" ]]; then
    kickstart_dir=$(printf '%s\n' "$CONFIG_YAML" | yq eval -r '.plugins."kickstart.nvim".directory')
    # Expand variables in the directory path
    eval kickstart_dir="$kickstart_dir"

    if [[ ! -d "$kickstart_dir" ]]; then
        echo "${TOOLS} Installing kickstart.nvim..."
        git clone "$(printf '%s\n' "$CONFIG_YAML" | yq eval -r '.plugins."kickstart.nvim".url')" "$kickstart_dir"
        update_action_status "kickstart.nvim"
    else
        echo "${SUCCESS} kickstart.nvim is already installed."
        update_action_status "kickstart.nvim"
    fi
elif [[ "$kickstart_action" == "uninstall" ]]; then
    kickstart_dir=$(printf '%s\n' "$CONFIG_YAML" | yq eval -r '.plugins."kickstart.nvim".directory')
    eval kickstart_dir="$kickstart_dir"

    if [[ -d "$kickstart_dir" ]]; then
        echo "${REMOVE} Uninstalling kickstart.nvim..."
        rm -rf "$kickstart_dir"
        update_action_status "kickstart.nvim"
    else
        echo "${INFO} kickstart.nvim is not installed. Nothing to uninstall."
        update_action_status "kickstart.nvim"
    fi
elif [[ "$kickstart_action" == "skip" ]]; then
    echo "${INFO} Skipping kickstart.nvim as per config.yaml."
else
    echo "${WARNING} Invalid action for kickstart.nvim: '$kickstart_action'. Skipping."
fi

# Install Neovim dependencies based on the action in config.yaml
neovim_action=$(printf '%s\n' "$CONFIG_YAML" | yq eval -r '.packages.neovim.action')

if [[ "$neovim_action" == "install" ]]; then
    echo "${TOOLS} Installing Neovim dependencies..."
    if [[ $DARWIN == 0 ]]; then
        brew install --quiet neovim 2> /dev/null || true
    else
        brew install --quiet neovim 2> /dev/null || true
    fi
    echo "${SUCCESS} Neovim dependencies installed."
elif [[ "$neovim_action" == "uninstall" ]]; then
    echo "${REMOVE} Uninstalling Neovim and its dependencies..."
    brew uninstall --quiet neovim 2> /dev/null || true
    echo "${SUCCESS} Neovim dependencies uninstalled."
elif [[ "$neovim_action" == "skip" ]]; then
    echo "${INFO} Skipping Neovim dependencies as per config.yaml."
else
    echo "${WARNING} Invalid action for Neovim: '$neovim_action'. Skipping."
fi

# Additional configuration and logic

# Configure OSC52 clipboard support if Neovim is installed
if [[ "$neovim_action" == "install" ]]; then
    config_files=$(find -L ~/.config -type f -exec grep -l 'unnamedplus' {} +)
    echo "----------------------------------------"
    echo "FOUND files with 'unnamedplus':"
    printf "%s\n" "$config_files"
    echo "----------------------------------------"

# Use a heredoc to store the code block in a variable which is used to activate clipboard over SSH
code_to_add=$(cat <<'EOF'
-- Added by Synology-Homebrew OSC52
vim.g.clipboard = {
    name = 'OSC52',
    copy = {
        ['+'] = require('vim.ui.clipboard.osc52').copy('+'),
        ['*'] = require('vim.ui.clipboard.osc52').copy('*'),
    },
    paste = {
        ['+'] = require('vim.ui.clipboard.osc52').paste('+'),
        ['*'] = require('vim.ui.clipboard.osc52').paste('*'),
    },
}
EOF
)

# Check if any files are found
if [[ -n "$config_files" ]]; then
    echo "Processing files:"
    while IFS= read -r config_file; do
        echo "Checking: $config_file"
        if ! grep -q "Added by Synology-Homebrew OSC52" "$config_file"; then
            echo "Adding OSC52 code to $config_file"
            if func_sed "/unnamedplus/ r /dev/stdin" "$config_file" <<<"$code_to_add"; then
                echo "OSC52 code successfully added to $config_file"
            else
                echo "Error: Failed to apply sed to $config_file" >&2
                continue
            fi
        else
            echo "OSC52 code already exists in $config_file"
        fi
    done <<< "$config_files"
else
    echo "No file containing 'unnamedplus' found in ~/.config folder."
fi

    # Install additional packages for Neovim
    echo "----------------------------------------"
    if [[ -n "$CONFIG_YAML" ]]; then
        if [[ "$neovim_action" == "install" ]]; then
            echo "Installing additional Neovim components..."

            # Install or upgrade pynvim
            if ! pip3 show pynvim &> /dev/null; then
                echo "pynvim is not installed. Installing pynvim..."
                pip3 install pynvim --break-system-packages
            else
                echo "pynvim is already installed. Upgrading pynvim..."
                pip3 install --upgrade pynvim --break-system-packages
            fi

            # Upgrade pip
            python3 -m pip install --upgrade pip --break-system-packages

            echo "npm check:"
            # Check if npm is installed, if not, install it
            if ! brew list npm &> /dev/null; then
                echo "npm is not installed. Installing npm..."
                brew install --quiet npm
            fi

            # Ensure icu4c is installed
            if ! brew list icu4c &>/dev/null; then
                echo "icu4c is not installed. Installing icu4c..."
                brew install icu4c
            else
                echo "icu4c is already installed."
            fi

            # Check if icu4c is already linked
            if ! brew list --versions icu4c &>/dev/null; then
                echo "Linking icu4c libraries..."
                brew link --force icu4c
            else
                echo "icu4c is already linked."
            fi

            # Remove existing global node_modules directory
            sudo rm -rf "$HOMEBREW_PATH/lib/node_modules"

            # Run the postinstall step for Node.js
            brew postinstall node

            # Disable npm funding messages globally
            sudo npm config set fund false --location=global

             # Install neovim globally using npm
            echo "installing neovim with npm."
            [[ ! -d ~/.npm ]] && mkdir ~/.npm
            sudo chown -R $USERNAME:$USERGROUP ~/.npm
            sudo npm install -g neovim@latest

            echo "checking neovim gem..."
            if ! gem list -i neovim; then
                gem install neovim --no-document
            fi

            # Check if a compatible version of Bundler is installed
            echo "checking gem bundler..."
            if ! gem list -i bundler; then
                gem install bundler -v '< 2.5' --no-document
            fi

            # Clone fzf-git.sh into scripts directory for fzf git keybindings. This will be sourced in .profile
            echo "Cloning fzf-git.sh into ~/.scripts directory"
            mkdir -p ~/.scripts && curl -o ~/.scripts/fzf-git.sh https://raw.githubusercontent.com/junegunn/fzf-git.sh/main/fzf-git.sh
        else
            echo "SKIPPING: Neovim components as config.yaml action is not set to 'install'."
        fi
    else
        echo "SKIPPING: Neovim components installation. This is expected when running this script independently."
    fi
fi

# Write updated YAML back to the temporary file
[[ -n $temp_file ]] && printf '%s\n' "$CONFIG_YAML" > "$temp_file"

# Perform cleanup only if run directly
if [[ "$CALLED_BY_MAIN" -eq 0 ]]; then
    echo "${REMOVE} Performing cleanup since script was run directly."
    func_cleanup_exit 0
else
    echo "${INFO} Skipping cleanup because the main script is managing it."
fi
