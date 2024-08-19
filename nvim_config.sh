#!/bin/bash

echo "Successfully called $(basename "$0")"

source "./functions.sh"

temp_file=$1

# Read YAML from the temporary file
[[ -n $temp_file ]] && CONFIG_YAML=$(<"$temp_file")

# For an independent manual run of this script, we add packages to an empty CONFIG_YAML
if [[ -z $temp_file ]]; then
    CONFIG_YAML_PATH="./config.yaml"

    # Ensure config.yaml exists
    if [[ ! -f "$CONFIG_YAML_PATH" ]]; then
        echo "config.yaml not found in this directory"
        exit 1
    fi

    echo "-----------------------------------------------------------------"
    read -p "Would you like to check and install neovim dependencies? (y/n): " answer
    if [[ "$answer" = "y" ]]; then
        CONFIG_YAML=$(yq '.packages.neovim += {install: "true"}' "$CONFIG_YAML_PATH")
    fi
    read -p "Would you like to check and install kickstart.nvim? (y/n): " answer
    if [[ "$answer" = "y" ]]; then
        CONFIG_YAML=$(yq '.plugins."kickstart.nvim" += {install: "true"}' "$CONFIG_YAML_PATH")
    fi
fi

# Function to update the install status in the YAML
update_install_status() {
    local plugin="$1"
    CONFIG_YAML=$(echo "$CONFIG_YAML" | yq ".plugins[\"$plugin\"].install = \"handled\"")
}

# Install kickstart.nvim if install is true in config.yaml
if [[ $(echo "$CONFIG_YAML" | yq -r '.plugins."kickstart.nvim".install') == "true" ]]; then
    kickstart_dir=$(echo "$CONFIG_YAML" | yq -r '.plugins."kickstart.nvim".directory')
    eval kickstart_dir="$kickstart_dir"

    if [[ ! -d "$kickstart_dir" ]]; then
        echo "Installing kickstart.nvim..."
        git clone "$(echo "$CONFIG_YAML" | yq -r '.plugins."kickstart.nvim".url')" "$kickstart_dir"
        update_install_status "kickstart.nvim"
    else
        update_install_status "kickstart.nvim"
        echo "kickstart.nvim is already installed."
    fi
fi

config_files=$(find -L ~/.config -type f -exec grep -l 'unnamedplus' {} +)
echo "----------------------------------------"
echo "FOUND files with 'unnamedplus':"
echo "$config_files"
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
    if [[ $(echo "$CONFIG_YAML" | yq -r '.packages.neovim.install') == "true" ]]; then
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
        if ! command -v npm &> /dev/null; then
            echo "npm is not installed. Installing npm..."
            brew install --quiet npm
        fi
        rm -rf /home/linuxbrew/.linuxbrew/lib/node_modules
        brew postinstall node
        npm install -g npm@latest
        npm config set fund false --location=global
        npm install -g neovim@latest

        echo
        echo -e "Checking for gem updates:\n"
        # Check for outdated gems and update them
        if [[ -n $(gem outdated) ]]; then
            gem update
        fi

        # Install the neovim gem if it's not already installed
        if ! gem list neovim -i; then
            gem install neovim
        fi
    else
        echo "SKIPPING: neovim components as config.yaml install flag is set to false."
    fi
else
    echo "SKIPPING: neovim components installation. This is expected when running this script independently."
fi

# Write updated YAML back to the temporary file
[[ -n $temp_file ]] && echo "$CONFIG_YAML" > "$temp_file"
