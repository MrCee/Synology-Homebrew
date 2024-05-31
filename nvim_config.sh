#!/bin/bash

CONFIG_JSON="$1"

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
            echo "Code successfully added to $config_file"
        else
            echo "Code already exists in $config_file"
        fi
    done
else
    echo "No file containing 'unnamedplus' found in ~/.config folder."
fi

if [[ -z "$CONFIG_JSON" ]]; then
echo "-----------------------------------------------------------------"
    read -p "Would you like to check and install neovim dependencies? (y/n): " answer
    if [[ "$answer" = "y" ]]; then
        CONFIG_JSON='{"packages":{"neovim":{"install":true}}}'
    fi
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
