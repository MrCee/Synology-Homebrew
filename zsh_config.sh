#!/bin/bash

# Function to install bat theme if required
install_bat_theme() {
    local theme_name="tokyonight_night"

    # Check if bat package installation is required
    if [[ $(echo "$CONFIG_JSON" | jq -r '.packages."bat".install') == "true" ]]; then
        echo "Installing bat theme: $theme_name"
        
        # Create themes directory if it doesn't exist
        mkdir -p "$(bat --config-dir)/themes"
        
        # Change to themes directory
        cd "$(bat --config-dir)/themes" || exit
        
        # Download the theme
        curl -O "https://raw.githubusercontent.com/folke/tokyonight.nvim/main/extras/sublime/${theme_name}.tmTheme"
        
        # Rebuild bat cache
        bat cache --build
        
        # Verify theme installation
        if bat --list-themes | grep -q "$theme_name"; then
            echo "$theme_name theme installed successfully"
            echo "--theme=\"$theme_name\"" >> "$(bat --config-dir)/config"
        else
            echo "Failed to install $theme_name theme"
        fi
    fi
}

# Main script logic

# Check if CONFIG_JSON_PATH is provided as an argument, otherwise use default
CONFIG_JSON_PATH="${1:-./config.json}"

# Read the content of JSON into the CONFIG_JSON variable
CONFIG_JSON=$(<"$CONFIG_JSON_PATH")

# Install bat theme if needed
install_bat_theme



