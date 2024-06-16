#!/bin/bash

# Function to install bat theme if required
install_bat_theme() {
    local theme_name="tokyonight_night"

    # Check if bat package installation is required
    if [[ $(echo "$CONFIG_JSON" | jq -r '.packages.bat.install') == true ]]; then
        echo "Installing bat theme: $theme_name"
        
        # Create themes directory if it doesn't exist
        mkdir -p "$(bat --config-dir)/themes"
        
        # Change to themes directory
        cd "$(bat --config-dir)/themes" || exit
        
        # Download the theme
        curl -O "https://raw.githubusercontent.com/folke/tokyonight.nvim/main/extras/sublime/${theme_name}.tmTheme"
        
        # Rebuild bat cache
        bat cache --build
        
        # Verify theme installation and check if theme is already in the config file
        if bat --list-themes | grep -q "$theme_name" && ! grep -q "\--theme=\"$theme_name\"" "$(bat --config-dir)/config"; then
            echo "bat theme: $theme_name installed successfully"
            echo "--theme=\"$theme_name\"" >> "$(bat --config-dir)/config"
        else
            echo "bat theme: $theme_name verified and is installed"
        fi
    fi
}

# Main
echo "Sucessfully called $(basename "$0")"

CONFIG_JSON="$1"

[[ -z "$CONFIG_JSON" ]] && CONFIG_JSON=$(cat "./config.json")

# Check if the JSON has data
if [ -z "$CONFIG_JSON" ]; then
    echo "Error: JSON configuration file not found"
    exit 1
fi

# Install bat theme if needed
install_bat_theme

