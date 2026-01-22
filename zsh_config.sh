#!/usr/bin/env bash
set -e

if [[ "${INSTALL_MODE:-minimal}" == "minimal" ]]; then
  echo "❌ ERROR: zsh_config.sh must never run in minimal install mode"
  echo "   This would violate minimal shell guarantees."
  exit 1
fi

source ./functions.sh

# Function to install zsh plugins
install_zsh_plugins() {
    echo "install_zsh_plugins..."

    local default_plugins=("git" "web-search")
    local plugins_array=("${default_plugins[@]}")

    # Use yq to get the list of plugins to add where action is "install" and directory contains custom/plugins
    local add_plugins
    add_plugins=$(yq eval -r '
      .plugins | to_entries[] |
      select(.value.action == "install" and (.value.directory | contains("custom/plugins"))) |
      .key' <<< "$CONFIG_YAML")

    # Iterate over the add_plugins, appending them to plugins_array
    while IFS= read -r plugin; do
        # Append only non-empty plugins
        if [[ -n "$plugin" ]]; then
            plugins_array+=("$plugin")
        fi
    done <<< "$add_plugins"

    # Join the plugins array into a space-separated string
    local plugins="${plugins_array[*]}"

    # Update ~/.zshrc with the selected plugins
    func_sed "s|^plugins=.*$|plugins=($plugins)|" ~/.zshrc
}

# Function to uninstall zsh plugins
uninstall_zsh_plugins() {
    echo "uninstall_zsh_plugins..."

    # Reset to default plugins
    local default_plugins=("git" "web-search")
    local plugins="${default_plugins[*]}"

    # Update ~/.zshrc with the default plugins
    func_sed "s|^plugins=.*$|plugins=($plugins)|" ~/.zshrc
}

# Function to install Powerlevel10k theme if required
install_powerlevel10k_theme() {
    echo "install_powerlevel10k_theme..."
    cp "$SCRIPT_DIR/profile-templates/p10k-profile-template" ~/.p10k.zsh

    # Ensure the theme is set to Powerlevel10k
    func_sed 's|^ZSH_THEME=.*$|ZSH_THEME="powerlevel10k/powerlevel10k"|' ~/.zshrc

    if ! grep -q "Enable Powerlevel10k instant prompt" ~/.zshrc; then
        echo '# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi
' | cat - ~/.zshrc > /tmp/.zshrc && mv /tmp/.zshrc ~/.zshrc
    fi

    # Ensure the Powerlevel10k sourcing line is in ~/.zshrc
    local p10k_line='[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh'

    # Check if the line already exists in ~/.zshrc
    if ! grep -Fxq "$p10k_line" ~/.zshrc; then
        echo "Adding Powerlevel10k source line to ~/.zshrc..."
        echo -e "\n# Source Powerlevel10k if installed\n# To customize prompt, run \`p10k configure\` or edit ~/.p10k.zsh." >> ~/.zshrc
        echo "$p10k_line" >> ~/.zshrc
    else
        echo "Powerlevel10k source line already exists in ~/.zshrc."
    fi
}

# Function to uninstall Powerlevel10k theme
uninstall_powerlevel10k_theme() {
    echo "uninstall_powerlevel10k_theme..."

    # Remove .p10k.zsh file
    rm -f ~/.p10k.zsh

    # Reset ZSH_THEME to default
    func_sed 's|^ZSH_THEME=.*$|ZSH_THEME="robbyrussell"|' ~/.zshrc

    # Remove Powerlevel10k instant prompt block
    func_sed '/Enable Powerlevel10k instant prompt/,/fi/d' ~/.zshrc

    # Remove Powerlevel10k source line
    # Use "#" delimiter:
	func_sed "\#\[\[ ! -f ~/.p10k.zsh \]\] \|\| source ~/.p10k.zsh#d" ~/.zshrc
}

# Function to install bat theme if required
install_bat_theme() {
    local theme_name="tokyonight_night"
    echo "Installing bat theme: $theme_name"
    mkdir -p "$(bat --config-dir)/themes"
    cd "$(bat --config-dir)/themes" || exit
    curl -O "https://raw.githubusercontent.com/folke/tokyonight.nvim/main/extras/sublime/${theme_name}.tmTheme"
    bat cache --build
    if bat --list-themes | grep -q "$theme_name" && ! grep -q "\--theme=\"$theme_name\"" "$(bat --config-dir)/config"; then
        echo "bat theme: $theme_name installed successfully"
        echo "--theme=\"$theme_name\"" >> "$(bat --config-dir)/config"
    else
        echo "bat theme: $theme_name verified and is installed"
    fi
}

# Function to uninstall bat theme
uninstall_bat_theme() {
    local theme_name="tokyonight_night"
    echo "Uninstalling bat theme: $theme_name"
    rm -f "$(bat --config-dir)/themes/${theme_name}.tmTheme"
    bat cache --build
    func_sed "/--theme=\"$theme_name\"/d" "$(bat --config-dir)/config"
}

# Main
echo "Successfully called $(basename "$0")"
SCRIPT_DIR=$(realpath "$(dirname "$0")")
CONFIG_YAML="$1"

# Load configuration from config.yaml if not provided as an argument
[[ -z "$CONFIG_YAML" ]] && CONFIG_YAML=$(cat "./config.yaml")

if [[ -z "$CONFIG_YAML" ]]; then
    echo "Error: YAML configuration file not found"
    exit 1
fi

# Handle zsh plugins
zsh_plugins_action=$(printf '%s\n' "$CONFIG_YAML" | yq eval -r '.plugins | to_entries[] | select(.value.directory | contains("custom/plugins")) | .value.action' | uniq)

if [[ "$zsh_plugins_action" == "install" ]]; then
    install_zsh_plugins
elif [[ "$zsh_plugins_action" == "uninstall" ]]; then
    uninstall_zsh_plugins
fi

# Handle bat package action
bat_action=$(printf '%s\n' "$CONFIG_YAML" | yq eval -r '.packages.bat.action')

if [[ "$bat_action" == "install" ]]; then
    if [[ -x $(command -v bat) ]]; then
        install_bat_theme
    else
        echo "bat not installed. Cannot install theme."
    fi
elif [[ "$bat_action" == "uninstall" ]]; then
    if [[ -x $(command -v bat) ]]; then
        uninstall_bat_theme
    else
        echo "bat not installed. Nothing to uninstall."
    fi
fi

# Handle powerlevel10k plugin action
p10k_action=$(printf '%s\n' "$CONFIG_YAML" | yq eval -r '.plugins.powerlevel10k.action')

if [[ "$p10k_action" == "install" ]]; then
    install_powerlevel10k_theme
elif [[ "$p10k_action" == "uninstall" ]]; then
    uninstall_powerlevel10k_theme
fi

