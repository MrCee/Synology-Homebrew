#!/bin/bash

temp_file=$1

# Read JSON from the temporary file
[[ -n $temp_file ]] && CONFIG_JSON=$(<"$temp_file")

# For an independent manual run of this script we add packages to an empty CONFIG_JSON
if [[ -z "$CONFIG_JSON" ]]; then
    CONFIG_JSON_PATH="./config.json"

    # Ensure config.json exists
    if [[ ! -f "$CONFIG_JSON_PATH" ]]; then
        echo "config.json not found in this directory"
        exit 1
    fi

    echo "-----------------------------------------------------------------"
    read -p "Would you like to check and install neovim dependencies? (y/n): " answer
    if [[ "$answer" = "y" ]]; then
        CONFIG_JSON=$(jq '.packages.neovim += {"install": true}' "$CONFIG_JSON_PATH")
    fi 
    read -p "Would you like to check and install kickstart.nvim? (y/n): " answer
    if [[ "$answer" = "y" ]]; then
        CONFIG_JSON=$(jq '.plugins."kickstart.nvim" += {"install": true}' "$CONFIG_JSON_PATH")
    fi
fi

# Function to update the install status in the JSON
update_install_status() {
    local plugin="$1"
    CONFIG_JSON=$(echo "$CONFIG_JSON" | jq --arg plugin "$plugin" '.plugins[$plugin].install = "handled"')
}

#Install kickstart.nvim if install is true in config.json 
if [[ $(echo "$CONFIG_JSON" | jq -r '.plugins."kickstart.nvim".install') == "true" ]]; then
    kickstart_dir=$(echo "$CONFIG_JSON" | jq -r '.plugins."kickstart.nvim".directory')
    eval kickstart_dir="$kickstart_dir"

    if [[ ! -d "$kickstart_dir" ]]; then
        echo "Installing kickstart.nvim..."
        git clone "$(echo "$CONFIG_JSON" | jq -r '.plugins."kickstart.nvim".url')" "$kickstart_dir"
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
            sed -i "/unnamedplus/ r /dev/stdin" "$config_file" <<<"$code_to_add"
            echo "OSC52 code for remote/system clipbard successfully added to $config_file"
        else
            echo "OSC52 code for remote/system clipboard already exists in $config_file"
        fi
    done
else
    echo "No file containing 'unnamedplus' found in ~/.config folder."
fi

# Install additional packages for neovim
echo "-----------------------------------------------------------------"
if [[ -n "$CONFIG_JSON" ]]; then
    if [[ $(echo "$CONFIG_JSON" | jq -r '.packages.neovim.install') = true ]]; then
        echo "Installing additional neovim components"
        [[ ! $(pip3 show pynvim) ]] && pip3 install pynvim --break-system-packages
        echo Checking for gem updates
        [[ -n $(gem outdated) ]] && gem update
        [[ $(gem list neovim -i) ]] && gem install neovim
        [[ ! -e ~/.scripts/fzf-git.sh ]] && mkdir -p ~/.scripts && curl -o ~/.scripts/fzf-git.sh https://raw.githubusercontent.com/junegunn/fzf-git.sh/main/fzf-git.sh
    else
        echo "SKIPPING: neovim components as config.json install flag is set to false."
    fi
else
    echo "SKIPPING: neovim components installation. This is expected when running this script independently."
fi

# Write updated JSON back to the temporary file
[[ -n $temp_file ]] && echo "$CONFIG_JSON" > "$temp_file"

