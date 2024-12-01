#!/bin/bash

# Change to the script directory
cd "$SCRIPT_DIR" || { echo "Failed to change directory to $SCRIPT_DIR" >&2; exit 1; }
echo "Working directory: $(pwd)"

source ./functions.sh

install_zsh_plugins() {
    echo "install_zsh_plugins..."

    local default_plugins=("git" "web-search")
    local plugins_array=("${default_plugins[@]}")

    # Use yq to get the list of plugins to add where action is "install" and directory contains custom/plugins
    local add_plugins
    add_plugins=$(yq eval -r '
      .plugins | to_entries[] |
      select(.value.action == "install") |
      .key' <<< "$CONFIG_YAML")

    # Iterate over the add_plugins, appending them to plugins_array and cloning them
    while IFS= read -r plugin; do
        # Append only non-empty plugins
        if [[ -n "$plugin" ]]; then
            plugins_array+=("$plugin")

            # Retrieve the plugin's URL and directory from config.yaml
            local plugin_url
            local plugin_dir
            plugin_url=$(yq eval -r ".plugins[\"$plugin\"].url" <<< "$CONFIG_YAML")
            plugin_dir=$(yq eval -r ".plugins[\"$plugin\"].directory" <<< "$CONFIG_YAML")

            # Expand the tilde (~) to the home directory
            plugin_dir=${plugin_dir/#\~/$HOME}

            # Check if the plugin directory already exists
            if [[ ! -d "$plugin_dir" ]]; then
                echo "📥 Installing plugin: $plugin"
                echo "Cloning from $plugin_url to $plugin_dir"

                # Create the parent directory if it doesn't exist
                mkdir -p "$(dirname "$plugin_dir")" || { echo "❌ Failed to create directory: $(dirname "$plugin_dir")"; failed_packages+=("$plugin"); continue; }

                # Clone the plugin repository
                if git clone "$plugin_url" "$plugin_dir"; then
                    echo "✅ Successfully cloned $plugin to $plugin_dir"
                    installed_packages+=("$plugin")
                else
                    echo "❌ Failed to clone $plugin from $plugin_url"
                    failed_packages+=("$plugin")
                fi
            else
                echo "ℹ️ Plugin $plugin already exists at $plugin_dir. Skipping clone."
                skipped_packages+=("$plugin")
            fi
        fi
    done <<< "$add_plugins"

    # Join the plugins array into a space-separated string
    local plugins="${plugins_array[*]}"

    # Update ~/.zshrc with the selected plugins
    func_sed "s|^plugins=.*$|plugins=($plugins)|" ~/.zshrc
}

uninstall_zsh_plugins() {
    echo "uninstall_zsh_plugins..."

    # Reset to default plugins
    local default_plugins=("git" "web-search")
    local plugins="${default_plugins[*]}"

    # Update ~/.zshrc with the default plugins
    func_sed "s|^plugins=.*$|plugins=($plugins)|" ~/.zshrc
}

# Function to install zsh themes
install_zsh_themes() {
    echo "Installing zsh themes..."

    # Extract themes to install
    local themes_to_install
    themes_to_install=$(printf '%s\n' "$CONFIG_YAML" | yq eval -r '
      .themes | to_entries[] |
      select(.value.action == "install") |
      .key' | uniq)

    while IFS= read -r theme; do
        # Proceed if theme is non-empty
        if [[ -n "$theme" ]]; then
            # Retrieve theme details from config.yaml
            local theme_url theme_dir
            theme_url=$(yq eval -r ".themes[\"$theme\"].url" <<< "$CONFIG_YAML")
            theme_dir=$(yq eval -r ".themes[\"$theme\"].directory" <<< "$CONFIG_YAML")
            theme_dir=${theme_dir/#\~/$HOME}  # Expand ~

            # Check if theme directory exists
            if [[ ! -d "$theme_dir" ]]; then
                echo "📥 Installing theme: $theme"
                echo "Cloning from $theme_url to $theme_dir"

                mkdir -p "$(dirname "$theme_dir")" || { echo "❌ Failed to create directory: $(dirname "$theme_dir")"; failed_packages+=("$theme"); continue; }

                if git clone "$theme_url" "$theme_dir"; then
                    echo "✅ Successfully cloned $theme to $theme_dir"
                    installed_packages+=("$theme")
                else
                    echo "❌ Failed to clone $theme from $theme_url"
                    failed_packages+=("$theme")
                fi
            else
                echo "ℹ️ Theme $theme already exists at $theme_dir. Skipping clone."
                skipped_packages+=("$theme")
            fi
        fi
    done <<< "$themes_to_install"
}

# Function to uninstall zsh themes
uninstall_zsh_themes() {
    echo "Uninstalling zsh themes..."

    # Extract themes to uninstall
    local themes_to_uninstall
    themes_to_uninstall=$(printf '%s\n' "$CONFIG_YAML" | yq eval -r '
      .themes | to_entries[] |
      select(.value.action == "uninstall") |
      .key' | uniq)

    while IFS= read -r theme; do
        if [[ -n "$theme" ]]; then
            echo "🗑️ Uninstalling theme: $theme"

            # Retrieve theme directory from config.yaml
            local theme_dir
            theme_dir=$(yq eval -r ".themes[\"$theme\"].directory" <<< "$CONFIG_YAML")
            theme_dir=${theme_dir/#\~/$HOME}  # Expand ~

            # Remove theme directory if it exists
            if [[ -d "$theme_dir" ]]; then
                echo "🗑️ Removing theme: $theme"
                rm -rf "$theme_dir" && echo "✅ Successfully removed $theme" || { echo "❌ Failed to remove $theme"; failed_packages+=("$theme"); }
            else
                echo "ℹ️ Theme directory $theme_dir does not exist. Skipping removal."
                skipped_packages+=("$theme")
            fi
        fi
    done <<< "$themes_to_uninstall"
}

# Function to install Powerlevel10k theme if required
install_powerlevel10k_theme() {
    echo "install_powerlevel10k_theme..."
    
    local theme_dir="$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
    local theme_repo="https://github.com/romkatv/powerlevel10k.git"

    # Clone the Powerlevel10k repository if it doesn't exist
    if [[ ! -d "$theme_dir" ]]; then
        echo "📥 Cloning Powerlevel10k into $theme_dir"
        mkdir -p "$(dirname "$theme_dir")" || { echo "❌ Failed to create directory: $(dirname "$theme_dir")"; exit 1; }
        git clone "$theme_repo" "$theme_dir" || { echo "❌ Failed to clone Powerlevel10k"; exit 1; }
        echo "✅ Successfully cloned Powerlevel10k"
    else
        echo "ℹ️ Powerlevel10k already exists at $theme_dir. Skipping clone."
    fi

    # Copy the profile template
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
    sed -i '/Enable Powerlevel10k instant prompt/,/fi/d' ~/.zshrc

    # Remove Powerlevel10k source line
    local p10k_line='[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh'
    func_sed "/$p10k_line/d" ~/.zshrc
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
SCRIPT_DIR=$(realpath "$(dirname "$0")")
CONFIG_YAML="$1"

# Change to the script directory
cd "$SCRIPT_DIR" || { echo "Failed to change directory to $SCRIPT_DIR" >&2; exit 1; }
echo "Working directory: $(pwd)"

source ./functions.sh

# Load configuration from config.yaml if not provided as an argument
[[ -z "$CONFIG_YAML" ]] && CONFIG_YAML=$(cat "./config.yaml")

if [[ -z "$CONFIG_YAML" ]]; then
    echo "Error: YAML configuration file not found"
    exit 1
fi


# Handle zsh plugins
zsh_plugins_action=$(printf '%s\n' "$CONFIG_YAML" | yq eval -r '
  .plugins | to_entries[] |
  select(.value.directory | contains("custom/plugins")) |
  .value.action' | uniq)

if [[ "$zsh_plugins_action" == "install" ]]; then
    install_zsh_plugins
elif [[ "$zsh_plugins_action" == "uninstall" ]]; then
    uninstall_zsh_plugins
fi

# Handle themes installation
themes_install_actions=$(printf '%s\n' "$CONFIG_YAML" | yq eval -r '
  .themes | to_entries[] |
  select(.value.action == "install") |
  .key' | uniq)

if [[ -n "$themes_install_actions" ]]; then
    install_zsh_themes
fi

# Handle themes uninstallation
themes_uninstall_actions=$(printf '%s\n' "$CONFIG_YAML" | yq eval -r '
  .themes | to_entries[] |
  select(.value.action == "uninstall") |
  .key' | uniq)

if [[ -n "$themes_uninstall_actions" ]]; then
    uninstall_zsh_themes
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
