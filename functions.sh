#!/bin/bash

# -----------------------------------------------
# functions.sh
# Description: Centralized functions for Homebrew and Zsh configurations.
# -----------------------------------------------

# Ensure the script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "🚫 This file should not be run directly; it should be sourced from the main script."
    exit 1
fi

# -----------------------------------------------
# Global Arrays for Summary Reporting
# -----------------------------------------------
# Declare global arrays without using `declare -g` (not supported in Bash 3.2)
installed_packages=()
uninstalled_packages=()
skipped_packages=()
failed_packages=()

# -----------------------------------------------
# Function: func_initialize_env_vars
# Description: Initializes environment variables based on the operating system.
# -----------------------------------------------
func_initialize_env_vars() {
    local arch os
    arch=$(uname -m)
    os=$(uname -s)

    if [[ "$os" == "Darwin" ]]; then
        DARWIN=1
        DEFAULT_GROUP="staff"


	if [[ "$arch" == "arm64" ]]; then
            # Path for Apple Silicon (M1, M2) macOS
            HOMEBREW_PATH="/opt/homebrew"
        else
            # Path for Intel macOS
            HOMEBREW_PATH="/usr/local"
        fi
	PROFILE=$(<./profile-templates/macos-profile-template)
    	PROFILE="${PROFILE//\$HOMEBREW_PATH/$HOMEBREW_PATH}"
	echo "$PROFILE" > ~/.zprofile
	source ~/.zprofile

	elif [[ "$os" == "Linux" ]]; then
        DARWIN=0
        # Path for Linuxbrew
        HOMEBREW_PATH="/home/linuxbrew/.linuxbrew"
        DEFAULT_GROUP="root"
    	PROFILE=$(<./profile-templates/synology-profile-template)
    	PROFILE="${PROFILE//\$HOMEBREW_PATH/$HOMEBREW_PATH}"
	echo "$PROFILE" > ~/.profile
	source ~/.profile
	else
        printf "❌ Unsupported OS: %s\n" "$os" >&2
        return 1
    fi

    # Export DARWIN and HOMEBREW_PATH after setting their values
    export DARWIN HOMEBREW_PATH DEFAULT_GROUP
}

# -----------------------------------------------
# Function: func_sudoers
# Description: Sets up the sudoers file with necessary permissions.
# Handles both macOS and Synology NAS environments.
# -----------------------------------------------
func_sudoers() {
    # Determine the sudoers directory and file path based on OS
    local sudoers_dir=""
    local current_user=""
    local is_synology=0

    if [[ $DARWIN -eq 0 ]]; then
        sudoers_dir="/etc/sudoers.d"
    elif [[ $DARWIN -eq 1 ]]; then
        sudoers_dir="/private/etc/sudoers.d"
    else
        # Detect Synology DSM
        if [[ -f /usr/syno/bin/synopkg ]]; then
            sudoers_dir="/etc/sudoers.d"
            is_synology=1
        else
            echo "❌ Unsupported OS."
            return 1
        fi
    fi

    sudoers_file="$sudoers_dir/custom_homebrew_sudoers"
    current_user=$(whoami)

    # Register the sudoers file for cleanup early
    export SUDOERS_FILE="$sudoers_file"

    # Check if sudoers setup is already done and the file exists
    if [[ "${SUDOERS_SETUP_DONE:-0}" -eq 1 && -f "$sudoers_file" ]]; then
        echo "✅ Sudoers setup already completed and sudoers file exists. Skipping."
        return 0
    fi

    # Proceed with sudoers setup
    echo "🛠️ Setting up sudoers file..."

    # Cache sudo credentials upfront
    sudo -k  # Reset cached credentials
    if ! sudo -v; then
        echo "❌ Failed to cache sudo credentials." >&2
        return 1
    fi

    # Ensure the sudoers directory exists
    if [[ ! -e "$sudoers_dir" ]]; then
        echo "🔧 Creating sudoers directory at '$sudoers_dir'..."
        sudo mkdir -p "$sudoers_dir" || { echo "❌ Failed to create '$sudoers_dir'."; return 1; }
    fi

    # Set the correct permissions for the sudoers directory
    sudo chmod 0755 "$sudoers_dir" || { echo "❌ Failed to set permissions for '$sudoers_dir'."; return 1; }

    # Install the sudoers file using tee
    echo "📝 Installing sudoers file at '$sudoers_file'..."
    sudo tee "$sudoers_file" > /dev/null <<EOF
Defaults syslog=authpriv
root ALL=(ALL) ALL
$current_user ALL=NOPASSWD: ALL
EOF

    # Set permissions for the sudoers file
    sudo chmod 0440 "$sudoers_file" || { echo "❌ Failed to set permissions for '$sudoers_file'."; return 1; }

    # Validate the sudoers file syntax only if visudo is available
    if command -v visudo > /dev/null 2>&1; then
        if ! sudo visudo -cf "$sudoers_file"; then
            echo "❌ Sudoers file syntax is invalid. Removing the faulty file." >&2
            sudo rm -f "$sudoers_file"
            return 1
        fi
        echo "✅ Sudoers file validated successfully."
    else
        if [[ $is_synology -eq 1 ]]; then
            echo "⚠️ Warning: 'visudo' not available on Synology NAS. Please ensure the sudoers file syntax is correct." >&2
        else
            echo "⚠️ Warning: 'visudo' not found. Skipping sudoers file validation." >&2
        fi
    fi

    echo "✅ Sudoers file installed successfully at '$sudoers_file'."

    # Mark sudoers setup as done
    export SUDOERS_SETUP_DONE=1
}

# -----------------------------------------------
# Function: func_cleanup_exit
# Description: Cleans up the sudoers file upon script exit or interruption.
# Arguments:
#   $1 - Exit code (default: 0)
# -----------------------------------------------
func_cleanup_exit() {
    local exit_code=${1:-0}  # Use $1 if provided, otherwise default to 0

    [[ $DEBUG == 1 ]] && echo "🔄 Debug: func_cleanup_exit called with exit code $exit_code."

    # Restore original stty settings
    if [[ -n "${orig_stty:-}" ]]; then
        stty "$orig_stty"
    fi

    if [[ $exit_code -eq 0 ]]; then
        echo "🎉 Script completed successfully."
    else
        echo "⚠️ Script exited with code $exit_code."
    fi

    # Perform cleanup if the sudoers file exists or if the flag is set
    if [[ -n "${SUDOERS_FILE:-}" ]]; then
        if [[ -f "$SUDOERS_FILE" ]]; then
            echo "🗑️ Removing sudoers file at '$SUDOERS_FILE'..."
            sudo rm -f "$SUDOERS_FILE" 2>/dev/null && echo "🗑️ Sudoers file removed."
        else
            echo "ℹ️ Sudoers file '$SUDOERS_FILE' does not exist. No removal needed."
        fi

        echo "🔒 Revoking sudo access..."
        sudo -k && echo "🔒 Sudo access revoked."

        # Reset the SUDOERS_SETUP_DONE flag
        export SUDOERS_SETUP_DONE=0
    else
        echo "🔍 Debug: SUDOERS_FILE is not set."
    fi

    # Unset the EXIT trap to prevent recursion
    trap - EXIT

    # Exit with the original exit code if it is non-zero
    if [[ $exit_code -ne 0 ]]; then
        exit "$exit_code"
    fi
}

# -----------------------------------------------
# Function: func_install_homebrew
# Description: Installs Homebrew if it's not already installed.
# -----------------------------------------------
func_install_homebrew() {
    if ! command -v brew &> /dev/null; then
        echo "🍺 Homebrew is not installed. Installing..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        if [[ $? -eq 0 ]]; then
            echo "✅ Homebrew installed successfully."
        else
            echo "❌ Homebrew installation failed." >&2
            exit 1
        fi
    else
        echo "🍺 Homebrew is already installed."
    fi
}

# -----------------------------------------------
# Function: func_initialize_homebrew
# Description: Initializes Homebrew environment variables.
# -----------------------------------------------
func_initialize_homebrew() {
    eval "$("$HOMEBREW_PATH"/bin/brew shellenv)"
}

# -----------------------------------------------
# Function: func_define_package_lists
# Description: Defines the list of packages to install based on the OS.
# -----------------------------------------------
func_define_package_lists() {
    packages=()
    if [[ $DARWIN -eq 0 ]]; then
        # Synology-specific packages
        packages=(
            glibc
            gcc
            git
            ruby
            clang-build-analyzer
            zsh
            yq
        )
    elif [[ $DARWIN -eq 1 ]]; then
        # macOS-specific packages
        packages=(
            git
            yq
            ruby
            python3
        )
    fi
}

# -----------------------------------------------
# Function: func_install_if_missing
# Description: Installs a package using Homebrew if it's not already installed.
# Arguments:
#   $1 - Package name
# -----------------------------------------------
func_install_if_missing() {
    local package="$1"
    if ! "$HOMEBREW_PATH"/bin/brew list --formula -1 | grep -Fxq "$package"; then
        echo "🛠️ Installing $package..."
        if "$HOMEBREW_PATH"/bin/brew install --quiet "$package"; then
            echo "✅ Successfully installed $package."
            installed_packages+=("$package")
        else
            echo "❌ Failed to install $package." >&2
            failed_packages+=("$package")
        fi
    else
        echo "✅ $package is already installed."
    fi
}

# -----------------------------------------------
# Function: func_uninstall_package
# Description: Uninstalls a package using Homebrew if it's installed.
# Arguments:
#   $1 - Package name
# -----------------------------------------------
func_uninstall_package() {
    local package="$1"
    if "$HOMEBREW_PATH"/bin/brew list --formula -1 | grep -Fxq "$package"; then
        echo "🚫 Uninstalling $package..."
        if "$HOMEBREW_PATH"/bin/brew uninstall --quiet "$package"; then
            echo "✅ Successfully uninstalled $package."
            uninstalled_packages+=("$package")
        else
            echo "❌ Failed to uninstall $package." >&2
            failed_packages+=("$package (uninstall)")
        fi
    else
        echo "⏭️ $package is not installed. Skipping uninstallation."
        skipped_packages+=("$package")
    fi
}

# -----------------------------------------------
# Function: func_upgrade_packages
# Description: Upgrades all installed Homebrew packages.
# -----------------------------------------------
func_upgrade_packages() {
    echo "🔄 Upgrading all Homebrew packages..."
    "$HOMEBREW_PATH"/bin/brew upgrade --quiet
    if [[ $? -eq 0 ]]; then
        echo "✅ Upgrade completed."
    else
        echo "❌ Upgrade encountered issues." >&2
        failed_packages+=("brew upgrade")
    fi
}

# -----------------------------------------------
# Function: process_additional_packages
# Description: Processes additional Homebrew packages based on config.yaml.
# Arguments:
#   $1 - Path to config.yaml
# -----------------------------------------------
process_additional_packages() {
    local config_file="$1"

    # Check if yq is installed
    if ! command -v yq &> /dev/null; then
        echo "❌ yq is not installed. Please install yq to manage packages." >&2
        failed_packages+=("yq (not installed)")
        return 1
    fi

    # Extract package names
    yq eval -r '.packages | keys | .[]' "$config_file" | while read -r pkg; do
        # Extract action for each package
        local action
        action=$(yq eval -r ".packages[\"$pkg\"].action" "$config_file")

        # Process based on action
        case "$action" in
            install)
                echo "🔧 Installing package: $pkg"
                func_install_if_missing "$pkg"
                ;;
            uninstall)
                echo "🗑️ Uninstalling package: $pkg"
                func_uninstall_package "$pkg"
                ;;
            skip)
                echo "⏭️ Skipping package: $pkg as per configuration."
                skipped_packages+=("$pkg")
                ;;
            *)
                echo "⚠️ Invalid action '$action' for package '$pkg' in config.yaml." >&2
                failed_packages+=("$pkg (invalid action)")
                ;;
        esac
    done
}

# -----------------------------------------------
# Function: func_sed
# Description: Performs a sed operation in a portable way.
# Arguments:
#   $1 - Sed expression
#   $2 - Input file
# -----------------------------------------------
func_sed() {
    local sed_expr="$1"
    local input_file="$2"
    local tmp_file

    tmp_file=$(mktemp) || { echo "❌ Error: Failed to create temporary file." >&2; return 1; }

    # Run sed and capture output
    if sed -E "$sed_expr" "$input_file" > "$tmp_file"; then
        # Check if the file actually needs changes
        if cmp -s "$input_file" "$tmp_file"; then
            echo "✅ Sed operation: No changes needed in '$input_file'."
        else
            mv "$tmp_file" "$input_file" || {
                echo "❌ Error: Failed to move temporary file to '$input_file'." >&2
                rm -f "$tmp_file"
                return 1
            }
            echo "🛠️ Sed operation: Fix applied in '$input_file' :: '$sed_expr'"
        fi
    else
        # Handle sed errors
        echo "❌ Error: Sed operation failed for '$input_file' with expression '$sed_expr'" >&2
        rm -f "$tmp_file"
        return 1
    fi
    # Cleanup temporary file
    rm -f "$tmp_file"

    return 0  # Ensure the function returns success
}

# -----------------------------------------------
# Zsh-Related Functions
# -----------------------------------------------

# -----------------------------------------------
# Function: install_zsh_plugins
# Description: Installs Zsh plugins as specified in the configuration.
# -----------------------------------------------
install_zsh_plugins() {
    echo "🔧 Installing Zsh plugins..."

    # Retrieve plugins to install from config.yaml
    local plugins=()
    while IFS= read -r plugin; do
        plugins+=("$plugin")
    done < <(yq eval -r '.plugins | to_entries[] | select(.value.action == "install") | .key' <<< "$CONFIG_YAML")

    for plugin in "${plugins[@]}"; do
        local plugin_url
        local plugin_dir

        # Retrieve the plugin's URL and directory from config.yaml
        plugin_url=$(yq eval -r ".plugins[\"$plugin\"].url" <<< "$CONFIG_YAML")
        plugin_dir=$(yq eval -r ".plugins[\"$plugin\"].directory" <<< "$CONFIG_YAML")
        plugin_dir=${plugin_dir/#\~/$HOME}  # Expand ~

        if [[ ! -d "$plugin_dir" ]]; then
            echo "📥 Installing plugin: $plugin"
            echo "Cloning from $plugin_url to $plugin_dir"
            mkdir -p "$(dirname "$plugin_dir")" || { echo "❌ Failed to create directory: $(dirname "$plugin_dir")"; failed_packages+=("$plugin"); continue; }
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
    done

    # Update ~/.zshrc with the selected plugins
    local plugins_list
    plugins_list=$(printf " %s" "${plugins[@]}")
    plugins_list=${plugins_list:1} # Remove leading space
    func_sed "s|^plugins=.*$|plugins=($plugins_list)|" ~/.zshrc
}

# -----------------------------------------------
# Function: uninstall_zsh_plugins
# Description: Uninstalls Zsh plugins as specified in the configuration.
# -----------------------------------------------
uninstall_zsh_plugins() {
    echo "🗑️ Uninstalling Zsh plugins..."

    # Retrieve plugins to uninstall from config.yaml
    local plugins=()
    while IFS= read -r plugin; do
        plugins+=("$plugin")
    done < <(yq eval -r '.plugins | to_entries[] | select(.value.action == "uninstall") | .key' <<< "$CONFIG_YAML")

    for plugin in "${plugins[@]}"; do
        local plugin_dir

        # Retrieve the plugin's directory from config.yaml
        plugin_dir=$(yq eval -r ".plugins[\"$plugin\"].directory" <<< "$CONFIG_YAML")
        plugin_dir=${plugin_dir/#\~/$HOME}  # Expand ~

        if [[ -d "$plugin_dir" ]]; then
            echo "🗑️ Uninstalling plugin: $plugin"
            rm -rf "$plugin_dir" && echo "✅ Successfully removed $plugin" || { echo "❌ Failed to remove $plugin"; failed_packages+=("$plugin"); }
        else
            echo "ℹ️ Plugin directory $plugin_dir does not exist. Skipping removal."
            skipped_packages+=("$plugin")
        fi
    done

    # Reset ~/.zshrc to remove uninstalled plugins
    local default_plugins=("git" "web-search")
    local updated_plugins=("${default_plugins[@]}")

    # Add remaining installed plugins
    while IFS= read -r plugin; do
        updated_plugins+=("$plugin")
    done < <(yq eval -r '.plugins | to_entries[] | select(.value.action == "install") | .key' <<< "$CONFIG_YAML")

    local plugins_list
    plugins_list=$(printf " %s" "${updated_plugins[@]}")
    plugins_list=${plugins_list:1} # Remove leading space
    func_sed "s|^plugins=.*$|plugins=($plugins_list)|" ~/.zshrc
}

# -----------------------------------------------
# Function: install_zsh_themes
# Description: Installs Zsh themes as specified in the configuration.
# -----------------------------------------------
install_zsh_themes() {
    echo "🔧 Installing Zsh themes..."

    # Retrieve themes to install from config.yaml
    local themes=()
    while IFS= read -r theme; do
        themes+=("$theme")
    done < <(yq eval -r '.themes | to_entries[] | select(.value.action == "install") | .key' <<< "$CONFIG_YAML")

    for theme in "${themes[@]}"; do
        local theme_url
        local theme_dir

        # Retrieve the theme's URL and directory from config.yaml
        theme_url=$(yq eval -r ".themes[\"$theme\"].url" <<< "$CONFIG_YAML")
        theme_dir=$(yq eval -r ".themes[\"$theme\"].directory" <<< "$CONFIG_YAML")
        theme_dir=${theme_dir/#\~/$HOME}  # Expand ~

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
    done

    # Update ~/.zshrc with the selected themes
    local themes_list
    themes_list=$(printf " %s" "${themes[@]}")
    themes_list=${themes_list:1} # Remove leading space
    func_sed "s|^ZSH_THEME=.*$|ZSH_THEME=\"${themes_list}\"|" ~/.zshrc
}

# -----------------------------------------------
# Function: uninstall_zsh_themes
# Description: Uninstalls Zsh themes as specified in the configuration.
# -----------------------------------------------
uninstall_zsh_themes() {
    echo "🗑️ Uninstalling Zsh themes..."

    # Retrieve themes to uninstall from config.yaml
    local themes=()
    while IFS= read -r theme; do
        themes+=("$theme")
    done < <(yq eval -r '.themes | to_entries[] | select(.value.action == "uninstall") | .key' <<< "$CONFIG_YAML")

    for theme in "${themes[@]}"; do
        local theme_dir

        # Retrieve the theme's directory from config.yaml
        theme_dir=$(yq eval -r ".themes[\"$theme\"].directory" <<< "$CONFIG_YAML")
        theme_dir=${theme_dir/#\~/$HOME}  # Expand ~

        if [[ -d "$theme_dir" ]]; then
            echo "🗑️ Uninstalling theme: $theme"
            rm -rf "$theme_dir" && echo "✅ Successfully removed $theme" || { echo "❌ Failed to remove $theme"; failed_packages+=("$theme"); }
        else
            echo "ℹ️ Theme directory $theme_dir does not exist. Skipping removal."
            skipped_packages+=("$theme")
        fi
    done

    # Reset ZSH_THEME to default or another specified theme
    local default_theme="robbyrussell"
    func_sed "s|^ZSH_THEME=.*$|ZSH_THEME=\"${default_theme}\"|" ~/.zshrc
}

# -----------------------------------------------
# Function: install_powerlevel10k_theme
# Description: Installs the Powerlevel10k Zsh theme.
# -----------------------------------------------
install_powerlevel10k_theme() {
    echo "🔧 Installing Powerlevel10k theme..."

    local theme_dir="$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
    local theme_repo="https://github.com/romkatv/powerlevel10k.git"

    # Clone the Powerlevel10k repository if it doesn't exist
    if [[ ! -d "$theme_dir" ]]; then
        echo "📥 Cloning Powerlevel10k into $theme_dir"
        mkdir -p "$(dirname "$theme_dir")" || { echo "❌ Failed to create directory: $(dirname "$theme_dir")"; exit 1; }
        if git clone "$theme_repo" "$theme_dir"; then
            echo "✅ Successfully cloned Powerlevel10k"
            installed_packages+=("powerlevel10k")
        else
            echo "❌ Failed to clone Powerlevel10k" >&2
            failed_packages+=("powerlevel10k")
            return 1
        fi
    else
        echo "ℹ️ Powerlevel10k already exists at $theme_dir. Skipping clone."
        skipped_packages+=("powerlevel10k")
    fi

    # Copy the profile template
    if [[ -f "$SCRIPT_DIR/profile-templates/p10k-profile-template" ]]; then
        cp "$SCRIPT_DIR/profile-templates/p10k-profile-template" ~/.p10k.zsh || {
            echo "❌ Failed to copy p10k profile template." >&2
            failed_packages+=("powerlevel10k p10k profile")
            return 1
        }
    else
        echo "❌ p10k-profile-template not found in $SCRIPT_DIR/profile-templates/" >&2
        failed_packages+=("powerlevel10k p10k profile")
        return 1
    fi

    # Ensure the theme is set to Powerlevel10k
    func_sed 's|^ZSH_THEME=.*$|ZSH_THEME="powerlevel10k/powerlevel10k"|' ~/.zshrc

    # Add Powerlevel10k instant prompt to ~/.zshrc if not present
    if ! grep -q "Enable Powerlevel10k instant prompt" ~/.zshrc; then
        echo '# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi
' | cat - ~/.zshrc > /tmp/.zshrc && mv /tmp/.zshrc ~/.zshrc
        echo "✅ Added Powerlevel10k instant prompt to ~/.zshrc"
    else
        echo "ℹ️ Powerlevel10k instant prompt already exists in ~/.zshrc."
    fi

    # Ensure the Powerlevel10k sourcing line is in ~/.zshrc
    local p10k_line='[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh'

    if ! grep -Fxq "$p10k_line" ~/.zshrc; then
        echo "Adding Powerlevel10k source line to ~/.zshrc..."
        echo -e "\n# Source Powerlevel10k if installed\n# To customize prompt, run \`p10k configure\` or edit ~/.p10k.zsh." >> ~/.zshrc
        echo "$p10k_line" >> ~/.zshrc
    else
        echo "ℹ️ Powerlevel10k source line already exists in ~/.zshrc."
    fi
}

# -----------------------------------------------
# Function: uninstall_powerlevel10k_theme
# Description: Uninstalls the Powerlevel10k Zsh theme.
# -----------------------------------------------
uninstall_powerlevel10k_theme() {
    echo "🗑️ Uninstalling Powerlevel10k theme..."

    # Remove .p10k.zsh file
    rm -f ~/.p10k.zsh && echo "✅ Removed ~/.p10k.zsh" || echo "❌ Failed to remove ~/.p10k.zsh"

    # Reset ZSH_THEME to default
    func_sed 's|^ZSH_THEME=.*$|ZSH_THEME="robbyrussell"|' ~/.zshrc

    # Remove Powerlevel10k instant prompt block from ~/.zshrc
    # Note: This sed command might not work correctly on macOS due to differences in sed.
    # We'll use a more portable approach.
    # Remove lines between "Enable Powerlevel10k instant prompt" and "fi"
    # Create a temporary file without those lines
    awk '/Enable Powerlevel10k instant prompt/,/fi/{next} {print}' ~/.zshrc > /tmp/.zshrc && mv /tmp/.zshrc ~/.zshrc
    echo "✅ Removed Powerlevel10k instant prompt block from ~/.zshrc"

    # Remove Powerlevel10k source line
    local p10k_line='[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh'
    func_sed "/$p10k_line/d" ~/.zshrc

    # Remove Powerlevel10k theme directory
    local theme_dir="$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
    if [[ -d "$theme_dir" ]]; then
        rm -rf "$theme_dir" && echo "✅ Removed Powerlevel10k theme directory." || echo "❌ Failed to remove Powerlevel10k theme directory."
    else
        echo "ℹ️ Powerlevel10k theme directory does not exist. Skipping removal."
    fi
}

# -----------------------------------------------
# Function: install_bat_theme
# Description: Installs a specific theme for bat.
# -----------------------------------------------
install_bat_theme() {
    local theme_name="tokyonight_night"
    echo "🔧 Installing bat theme: $theme_name"

    mkdir -p "$(bat --config-dir)/themes" || { echo "❌ Failed to create bat themes directory." >&2; return 1; }
    cd "$(bat --config-dir)/themes" || exit

    curl -O "https://raw.githubusercontent.com/folke/tokyonight.nvim/main/extras/sublime/${theme_name}.tmTheme" || {
        echo "❌ Failed to download bat theme." >&2
        return 1
    }

    bat cache --build
    if bat --list-themes | grep -q "$theme_name" && ! grep -q "\--theme=\"$theme_name\"" "$(bat --config-dir)/config"; then
        echo "✅ bat theme: $theme_name installed successfully"
        echo "--theme=\"$theme_name\"" >> "$(bat --config-dir)/config"
    else
        echo "ℹ️ bat theme: $theme_name verified and is installed"
    fi
}

# -----------------------------------------------
# Function: uninstall_bat_theme
# Description: Uninstalls a specific theme for bat.
# -----------------------------------------------
uninstall_bat_theme() {
    local theme_name="tokyonight_night"
    echo "🗑️ Uninstalling bat theme: $theme_name"

    rm -f "$(bat --config-dir)/themes/${theme_name}.tmTheme" && echo "✅ Removed bat theme: $theme_name" || echo "❌ Failed to remove bat theme: $theme_name"
    bat cache --build
    func_sed "/--theme=\"$theme_name\"/d" "$(bat --config-dir)/config"
}

# -----------------------------------------------
# Function: get_base_package
# Description: Extracts the base package name from a full package path.
# Arguments:
#   $1 - Full package name (e.g., "homebrew/core/git")
# -----------------------------------------------
get_base_package() {
    local full_package="$1"
    basename "$full_package"
}

# -----------------------------------------------
# Function: process_package
# Description: Processes a package based on the specified action.
# Arguments:
#   $1 - Package name
#   $2 - Action (install/uninstall/skip)
# -----------------------------------------------
process_package() {
    local package="$1"
    local action="$2"
    local base_package
    base_package=$(get_base_package "$package")

    case "$action" in
        install)
            func_install_if_missing "$base_package"
            ;;
        uninstall)
            func_uninstall_package "$base_package"
            ;;
        skip)
            echo "⏭️ ${base_package}: Skipping as per configuration."
            skipped_packages+=("$base_package")
            ;;
        *)
            echo "⚠️ Invalid action '$action' for package '$base_package' in config.yaml." >&2
            failed_packages+=("$base_package (invalid action)")
            ;;
    esac
}

# -----------------------------------------------
# Function: display_summary
# Description: Displays a summary of installed, uninstalled, skipped, and failed packages.
# -----------------------------------------------
display_summary() {
    echo -e "\n📋 Summary:"

    if [ ${#installed_packages[@]} -ne 0 ]; then
        echo -e "\n✅ Installed Packages:"
        for pkg in "${installed_packages[@]}"; do
            echo "  - $pkg"
        done
    fi

    if [ ${#uninstalled_packages[@]} -ne 0 ]; then
        echo -e "\n🗑️ Uninstalled Packages:"
        for pkg in "${uninstalled_packages[@]}"; do
            echo "  - $pkg"
        done
    fi

    if [ ${#skipped_packages[@]} -ne 0 ]; then
        echo -e "\n⏭️ Skipped Packages:"
        for pkg in "${skipped_packages[@]}"; do
            echo "  - $pkg"
        done
    fi

    if [ ${#failed_packages[@]} -ne 0 ]; then
        echo -e "\n❌ Failed Actions:"
        for pkg in "${failed_packages[@]}"; do
            echo "  - $pkg"
        done
    fi

    echo -e "\n✅ Script execution completed."
}

# -----------------------------------------------
# Function: install_zsh_themes_extended
# Description: Installs all specified Zsh themes, including optional ones like Powerlevel10k.
# -----------------------------------------------
install_zsh_themes_extended() {
    install_zsh_themes
    # Additional theme installations can be called here if needed
}

# -----------------------------------------------
# Function: uninstall_zsh_themes_extended
# Description: Uninstalls all specified Zsh themes, including optional ones like Powerlevel10k.
# -----------------------------------------------
uninstall_zsh_themes_extended() {
    uninstall_zsh_themes
    # Additional theme uninstallations can be called here if needed
}





# -----------------------------------------------
# Export functions for availability in subshells if needed
# -----------------------------------------------
# Note: Bash 3.2 on macOS may not support `export -f` for some functions.
# Use with caution and test accordingly.
export -f func_initialize_env_vars
export -f func_sudoers
export -f func_cleanup_exit
export -f func_install_homebrew
export -f func_initialize_homebrew
export -f func_define_package_lists
export -f func_install_if_missing
export -f func_uninstall_package
export -f func_upgrade_packages
export -f func_sed
export -f install_zsh_plugins
export -f uninstall_zsh_plugins
export -f install_zsh_themes
export -f uninstall_zsh_themes
export -f install_powerlevel10k_theme
export -f uninstall_powerlevel10k_theme
export -f install_bat_theme
export -f uninstall_bat_theme
export -f get_base_package
export -f process_package
export -f display_summary
export -f install_zsh_themes_extended
export -f uninstall_zsh_themes_extended


