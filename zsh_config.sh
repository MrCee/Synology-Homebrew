#!/bin/bash

cp ./$HOME/.cache
if [[ ! -e ~/.p10k.zsh && ! $(grep -q "Enable Powerlevel10k instant prompt" ~/.zshrc) ]]; then
  echo '# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi
' | cat - ~/.zshrc > temp && mv temp ~/.zshrc
fi


# Function to install bat theme if required
install_bat_theme() {
    local theme_name="tokyonight_night"

    if [[ $(echo "$CONFIG_YAML" | yq -r '.packages.bat.install') == true ]]; then
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
    fi
}

# Main
echo "Successfully called $(basename "$0")"

CONFIG_YAML="$1"

[[ -z "$CONFIG_YAML" ]] && CONFIG_YAML=$(cat "./config.yaml")

if [ -z "$CONFIG_YAML" ]; then
    echo "Error: YAML configuration file not found"
    exit 1
fi

install_bat_theme
