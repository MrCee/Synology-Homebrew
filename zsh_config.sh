#!/bin/bash


# File: zsh_config.sh

# Source the functions file
SCRIPT_DIR=$(dirname "$(realpath "$0")")
source "$SCRIPT_DIR/functions.sh"

# Load configuration from the first argument or read from config.yaml if not provided
CONFIG_YAML="${1:-$(<./config.yaml)}"

# Since CONFIG_YAML contains the content, remove file checks
echo "✅ Configuration loaded."

# Initialize environment variables (if needed)
func_initialize_env_vars

# Handle Zsh plugins and themes by calling the centralized functions
zsh_plugins_action=$(yq eval -r '.plugins | to_entries[] | select(.value.directory | contains("custom/plugins")) | .value.action' <<< "$CONFIG_YAML" | sort | uniq || echo "")
echo "🔍 zsh_plugins_action: '$zsh_plugins_action'"

if [[ "$zsh_plugins_action" == "install" ]]; then
    install_zsh_plugins
elif [[ "$zsh_plugins_action" == "uninstall" ]]; then
    uninstall_zsh_plugins
else
    echo "ℹ️ No action specified for Zsh plugins."
fi

themes_action=$(yq eval -r '.themes | to_entries[] | .value.action' <<< "$CONFIG_YAML" | sort | uniq || echo "")
echo "🔍 themes_action: '$themes_action'"

if [[ "$themes_action" == "install" ]]; then
    install_zsh_themes
elif [[ "$themes_action" == "uninstall" ]]; then
    uninstall_zsh_themes
else
    echo "ℹ️ No action specified for Zsh themes."
fi

# Handle specific theme installations like Powerlevel10k or bat if required
bat_action=$(yq eval -r '.packages.bat.action' <<< "$CONFIG_YAML" || echo "")
echo "🔍 bat_action: '$bat_action'"

if [[ "$bat_action" == "install" ]]; then
    if command -v bat &> /dev/null; then
        install_bat_theme
    else
        echo "bat not installed. Cannot install theme." >&2
    fi
elif [[ "$bat_action" == "uninstall" ]]; then
    if command -v bat &> /dev/null; then
        uninstall_bat_theme
    else
        echo "bat not installed. Nothing to uninstall." >&2
    fi
else
    echo "ℹ️ No action specified for bat theme."
fi

p10k_action=$(yq eval -r '.themes.powerlevel10k.action' <<< "$CONFIG_YAML" || echo "")
echo "🔍 p10k_action: '$p10k_action'"

if [[ "$p10k_action" == "install" ]]; then
    install_powerlevel10k_theme
elif [[ "$p10k_action" == "uninstall" ]]; then
    uninstall_powerlevel10k_theme
else
    echo "ℹ️ No action specified for Powerlevel10k theme."
fi

# Display summary of actions
display_summary

echo "✅ Zsh configuration completed successfully."


# Extract and filter alias commands directly from CONFIG_YAML
alias_commands=$(yq eval -r '
  (.packages + .plugins)
  | to_entries[]
  | select(.value.aliases != [] and .value.action != "uninstall")
  | .value.aliases
  | to_entries[]
  | select(.key != "" and .value != "")
  | "\(.key)=\(.value)"
' <<< "$CONFIG_YAML" | grep -v "^alias =$")

# Only proceed if alias_commands is not empty
if [[ -n "$alias_commands" ]]; then
    while IFS='=' read -r key value; do
        # Escape double quotes in the value
        value=$(printf '%s' "$value" | sed 's/"/\\"/g')

        # Format the alias command with the properly escaped value
        formatted_alias="alias ${key}=\"${value}\""

        if ! grep -qF "$formatted_alias" ~/.zshrc; then
            echo "Adding alias command: $formatted_alias"
            echo "$formatted_alias" >> ~/.zshrc
        else
            echo "Alias already exists: $formatted_alias"
        fi
    done <<< "$alias_commands"
else
    echo "No aliases to add."
fi

# Extract and filter eval commands directly from CONFIG_YAML
eval_commands=$(yq eval -r '
  (.packages + .plugins)
  | to_entries[]
  | select(.value.eval != [] and .value.action != "uninstall")
  | .value.eval[]
' <<< "$CONFIG_YAML" | grep -v "^$")

# Only proceed with the while loop if eval_commands is not empty
if [[ -n "$eval_commands" ]]; then
    while IFS= read -r eval_command; do
        # Escape double quotes in the eval command
        eval_command=$(printf '%s' "$eval_command" | sed 's/"/\\"/g')

        # Format the eval command for execution
        formatted_eval="eval \"\$($eval_command)\""

        # Check if the eval command already exists in ~/.zshrc
        if ! grep -qF "$formatted_eval" ~/.zshrc; then
            echo "Adding eval command: $formatted_eval"
            echo "$formatted_eval" >> ~/.zshrc
        else
            echo "Eval command already exists: $formatted_eval"
        fi
    done <<< "$eval_commands"
else
    echo "No eval commands to add."
fi

echo "✅ Zsh configuration completed successfully."




