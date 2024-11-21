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

config_files=$(find -L ~/.config -type f -exec grep -l 'unnamedplus' {} +)
echo "----------------------------------------"
echo "FOUND files with 'unnamedplus':"
printf "%s\n" "$config_files"
echo "----------------------------------------"

# Use a heredoc to store the code block in a variable which is used to activate clipboard over ssh
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
    for config_file in $config_files; do
        if ! grep -q "Added by Synology-Homebrew OSC52" "$config_file"; then
            # Add the code after the line containing "unnamedplus"
            func_sed "/unnamedplus/ r /dev/stdin" "$config_file" <<<"$code_to_add"
            echo "OSC52 code for remote/system clipboard successfully added to $config_file"
        else
            echo "OSC52 code for remote/system clipboard already exists in $config_file"
        fi
    done
else
    echo "No file containing 'unnamedplus' found in ~/.config folder."
fi

# Install additional packages for neovim
echo "----------------------------------------"
if [[ -n "$CONFIG_YAML" ]]; then
    if [[ $(printf '%s\n' "$CONFIG_YAML" | yq eval -r '.packages.neovim.install') == "true" ]]; then
        echo "Installing additional neovim components..."

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
sudo rm -rf /home/linuxbrew/.linuxbrew/lib/node_modules

# Run the postinstall step for Node.js
brew postinstall node

# Install the latest npm globally
sudo npm install -g npm@latest

# Disable npm funding messages globally
sudo npm config set fund false --location=global

# Install neovim globally using npm
sudo npm install -g neovim@latest

echo -e "Checking for gem updates:\n"

# Check if the neovim gem is installed; install if missing
if ! gem list -i neovim; then
    gem install neovim --no-document
fi

# Check if a compatible version of Bundler is installed
# Install Bundler if needed, but only if it's required for your project
if ! gem list -i bundler; then
    gem install bundler -v '< 2.5' --no-document
fi

# Clone fzf-git.sh into scripts directory for fzf git keybindings. This will be sources in .profile
echo Cloning fzf-git.sh into ~/.scripts directory
mkdir -p ~/.scripts && curl -o ~/.scripts/fzf-git.sh https://raw.githubusercontent.com/junegunn/fzf-git.sh/main/fzf-git.sh

else
        echo "SKIPPING: neovim components as config.yaml install flag is set to false."
    fi
# Perform cleanup only if run directly
if [[ "$CALLED_BY_MAIN" -eq 0 ]]; then
    echo "${REMOVE} Performing cleanup since script was run directly."
    func_cleanup_exit 0
else
    echo "${INFO} Skipping cleanup because the main script is managing it."
fi

