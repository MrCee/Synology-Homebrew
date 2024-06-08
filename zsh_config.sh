#!/bin/bash

# Bat is a better cat. Install a theme
if [[ $(echo config.json | jq -r '.packages."bat".install') == "true" ]]; then
mkdir -p "$(bat --config-dir)/themes"
cd "$(bat --config-dir)/themes"
# Replace _night in the lines below with _day, _moon, or _storm if needed.
curl -O https://raw.githubusercontent.com/folke/tokyonight.nvim/main/extras/sublime/tokyonight_night.tmTheme
bat cache --build
bat --list-themes | grep tokyo # should output "tokyonight_night"
echo '--theme="tokyonight_night"' >> "$(bat --config-dir)/config"
fi
