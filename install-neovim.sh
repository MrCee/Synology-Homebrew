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
    echo "${INFO} install-neovim.sh has been called by the main script with temp file: $temp_file"
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

    read -r -p "Would you like to check and install Neovim dependencies? (y/n): " answer
    if [[ "$answer" == "y" ]]; then
        CONFIG_YAML=$(printf '%s\n' "$CONFIG_YAML" | yq e '.packages.neovim.action = "install"')
    else
        CONFIG_YAML=$(printf '%s\n' "$CONFIG_YAML" | yq e '.packages.neovim.action = "skip"')
    fi

    read -r -p "Would you like to check and install kickstart.nvim? (y/n): " answer
    if [[ "$answer" == "y" ]]; then
        CONFIG_YAML=$(printf '%s\n' "$CONFIG_YAML" | yq e '.plugins."kickstart.nvim".action = "install"')
    else
        CONFIG_YAML=$(printf '%s\n' "$CONFIG_YAML" | yq e '.plugins."kickstart.nvim".action = "skip"')
    fi

    func_sudoers
fi

# Resolve authoritative Python interpreter from Homebrew first
PYTHON_CMD="${HOMEBREW_PATH}/bin/python3"
if [[ ! -x "$PYTHON_CMD" ]]; then
    PYTHON_CMD="$(command -v python3 2>/dev/null || true)"
fi

if [[ -z "$PYTHON_CMD" || ! -x "$PYTHON_CMD" ]]; then
    echo "${ERROR} Could not locate a usable python3 interpreter." >&2
    exit 1
fi

echo "${INFO} Using Python interpreter: $PYTHON_CMD"

# Define dedicated Neovim Python provider virtualenv
NVIM_PYTHON_VENV="${HOME}/.local/share/neovim-python"
NVIM_PYTHON_BIN="${NVIM_PYTHON_VENV}/bin/python3"
NVIM_HOST_EXPORT='export NVIM_PYTHON3_HOST_PROG="$HOME/.local/share/neovim-python/bin/python3"'
NVIM_INIT_LUA_LINE='vim.g.python3_host_prog = vim.fn.expand("$HOME/.local/share/neovim-python/bin/python3")'
NVIM_INIT_VIM_LINE='let g:python3_host_prog = expand("$HOME/.local/share/neovim-python/bin/python3")'

# Function to update the action status in the YAML
update_action_status() {
    local plugin="$1"
    CONFIG_YAML=$(printf '%s\n' "$CONFIG_YAML" | yq e ".plugins[\"$plugin\"].action = \"handled\"" -)
}

ensure_line_in_file() {
    local file="$1"
    local exact_line="$2"
    [[ -f "$file" ]] || touch "$file"
    if ! grep -Fqx "$exact_line" "$file" 2>/dev/null; then
        echo "$exact_line" >> "$file"
    fi
}

# Install kickstart.nvim based on the action in config.yaml
kickstart_action=$(printf '%s\n' "$CONFIG_YAML" | yq eval -r '.plugins."kickstart.nvim".action')

if [[ "$kickstart_action" == "install" ]]; then
    kickstart_dir=$(printf '%s\n' "$CONFIG_YAML" | yq eval -r '.plugins."kickstart.nvim".directory')
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
    brew install --quiet neovim 2>/dev/null || true
    echo "${SUCCESS} Neovim dependencies installed."
elif [[ "$neovim_action" == "uninstall" ]]; then
    echo "${REMOVE} Uninstalling Neovim and its dependencies..."
    brew uninstall --quiet neovim 2>/dev/null || true
    echo "${SUCCESS} Neovim dependencies uninstalled."
elif [[ "$neovim_action" == "skip" ]]; then
    echo "${INFO} Skipping Neovim dependencies as per config.yaml."
else
    echo "${WARNING} Invalid action for Neovim: '$neovim_action'. Skipping."
fi

# Additional configuration and logic
if [[ "$neovim_action" == "install" ]]; then
    config_files=$(find -L ~/.config -type f -exec grep -l 'unnamedplus' {} + 2>/dev/null || true)

    echo "----------------------------------------"
    echo "FOUND files with 'unnamedplus':"
    printf "%s\n" "$config_files"
    echo "----------------------------------------"

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

    if [[ -n "$config_files" ]]; then
        echo "Processing files:"
        while IFS= read -r config_file; do
            [[ -z "$config_file" ]] && continue
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

    echo "----------------------------------------"

    if [[ -n "$CONFIG_YAML" ]]; then
        if [[ "$neovim_action" == "install" ]]; then
            echo "Installing additional Neovim components..."

            echo "Ensuring Neovim Python provider virtualenv exists..."
            mkdir -p "${HOME}/.local/share"

            if [[ ! -x "$NVIM_PYTHON_BIN" ]]; then
                echo "Creating virtualenv at $NVIM_PYTHON_VENV"
                "$PYTHON_CMD" -m venv "$NVIM_PYTHON_VENV"
            else
                echo "Neovim Python provider virtualenv already exists."
            fi

            echo "Upgrading pip/setuptools/wheel inside Neovim virtualenv..."
            "$NVIM_PYTHON_BIN" -m pip install --upgrade pip setuptools wheel

            echo "Installing/upgrading pynvim inside Neovim virtualenv..."
            "$NVIM_PYTHON_BIN" -m pip install --upgrade pynvim

            echo "Ensuring shell export for NVIM_PYTHON3_HOST_PROG..."
            ensure_line_in_file "$HOME/.zshrc" "$NVIM_HOST_EXPORT"

            echo "Ensuring Neovim config points to dedicated python host..."
            mkdir -p "$HOME/.config/nvim"

            if [[ -f "$HOME/.config/nvim/init.lua" ]]; then
                ensure_line_in_file "$HOME/.config/nvim/init.lua" "$NVIM_INIT_LUA_LINE"
            elif [[ -f "$HOME/.config/nvim/init.vim" ]]; then
                ensure_line_in_file "$HOME/.config/nvim/init.vim" "$NVIM_INIT_VIM_LINE"
            else
                printf '%s\n' "$NVIM_INIT_LUA_LINE" > "$HOME/.config/nvim/init.lua"
            fi

            echo "npm check:"
            if ! brew list npm >/dev/null 2>&1; then
                echo "npm is not installed. Installing npm..."
                brew install --quiet npm
            fi

            if ! brew list icu4c >/dev/null 2>&1; then
                echo "icu4c is not installed. Installing icu4c..."
                brew install icu4c
            else
                echo "icu4c is already installed."
            fi

            echo "Ensuring icu4c libraries are linked..."
            brew link --force icu4c >/dev/null 2>&1 || true

            sudo rm -rf "$HOMEBREW_PATH/lib/node_modules"

            brew postinstall node || true

            sudo npm config set fund false --location=global

            echo -e "\nInstalling neovim with npm."
            [[ ! -d ~/.npm ]] && mkdir -p ~/.npm
            sudo npm install -g neovim@latest

            HOMEBREW_PREFIX=$(brew --prefix)

            [[ -d ~/.npm ]] && sudo chown -R "$USERNAME:$USERGROUP" ~/.npm
            [[ -d "$HOMEBREW_PREFIX/lib/node_modules" ]] && sudo chown -R "$USERNAME:$USERGROUP" "$HOMEBREW_PREFIX/lib/node_modules"
            [[ -e "$HOMEBREW_PREFIX/bin/npm" ]] && sudo chown "$USERNAME:$USERGROUP" "$HOMEBREW_PREFIX/bin/npm"
            [[ -e "$HOMEBREW_PREFIX/bin/npx" ]] && sudo chown "$USERNAME:$USERGROUP" "$HOMEBREW_PREFIX/bin/npx"
            [[ -e "$HOMEBREW_PREFIX/etc/npmrc" ]] && sudo chown "$USERNAME:$USERGROUP" "$HOMEBREW_PREFIX/etc/npmrc"

            echo "checking neovim gem..."
            if ! gem list -i neovim >/dev/null 2>&1; then
                gem install neovim --no-document
            fi

            echo "checking gem bundler..."
            if ! gem list -i bundler >/dev/null 2>&1; then
                gem install bundler -v '< 2.5' --no-document
            fi

            echo "Cloning fzf-git.sh into ~/.scripts directory"
            mkdir -p ~/.scripts && curl -fsSL -o ~/.scripts/fzf-git.sh https://raw.githubusercontent.com/junegunn/fzf-git.sh/main/fzf-git.sh

            echo "${SUCCESS} Neovim provider setup complete."
            echo "${INFO} Python host: $NVIM_PYTHON_BIN"
        else
            echo "SKIPPING: Neovim components as config.yaml action is not set to 'install'."
        fi
    else
        echo "SKIPPING: Neovim components installation. This is expected when running this script independently."
    fi
fi

# Write updated YAML back to the temporary file
[[ -n "$temp_file" ]] && printf '%s\n' "$CONFIG_YAML" > "$temp_file"

# Perform cleanup only if run directly
if [[ "$CALLED_BY_MAIN" -eq 0 ]]; then
    echo "${REMOVE} Performing cleanup since script was run directly."
    func_cleanup_exit 0
else
    echo "${INFO} Skipping cleanup because the main script is managing it."
fi

