#!/bin/bash

DEBUG=1
[[ $DEBUG -eq 1 ]] && echo "DEBUG mode on with strict -euo pipefail error handling" && set -euo pipefail

SCRIPT_PATH=$(realpath "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")

# Change to the script directory
cd "$SCRIPT_DIR" || { echo "Failed to change directory to $SCRIPT_DIR" >&2; exit 1; }
echo "Working directory: $(pwd)"

# Source the functions file
source "./functions.sh"

# Initialize environment variables
func_initialize_env_vars

# Save original stty settings and disable echoctl
orig_stty=$(stty -g)
export orig_stty
stty -echoctl

# Check if DARWIN was set correctly
echo "DARWIN: $DARWIN"
echo "HOMEBREW_PATH: $HOMEBREW_PATH"
echo "DEFAULT_GROUP: $DEFAULT_GROUP"

# Set Trap for EXIT to Handle Normal Cleanup
trap 'code=$?; func_cleanup_exit $code' EXIT

# Set Trap for Interruption Signals to Handle Cleanup
trap 'func_cleanup_exit 130' INT TERM HUP QUIT ABRT ALRM PIPE

# Setup sudoers file
func_sudoers

# Check if sudoers setup was successful before proceeding
if [[ "${SUDOERS_SETUP_DONE:-0}" -ne 1 ]]; then
    echo "Sudoers setup was not completed successfully. Exiting." >&2
    exit 1
fi

[[ $DEBUG -eq 1 ]] && echo "Debug: SUDOERS_FILE is set to '$SUDOERS_FILE'"

# Check if the script is being run as root
if [[ "$EUID" -eq 0 ]]; then
    echo "This script should not be run as root. Run it as a regular user, although we will need root password in a second..." >&2
    exit 1  # Triggers func_cleanup_exit via EXIT trap
fi

# Check prerequisites of this script
error=false
git_install_flag=false

if [[ $DARWIN -eq 0 ]]; then
    # Check if Synology Homes is enabled
    if [[ ! -d /var/services/homes/$(whoami) ]]; then
        echo "Synology Homes has NOT been enabled. Please enable in DSM Control Panel >> Users & Groups >> Advanced >> User Home." >&2
        error=true
    fi

    # Install Homebrew and required packages using functions.sh
    echo "Starting Homebrew setup for Synology (DARWIN=0)..."

    # Install Homebrew if necessary
    func_install_homebrew

    # Initialize Homebrew
    func_initialize_homebrew

    # Define package lists based on DARWIN
    func_define_package_lists

    # Initialize arrays for summary
    installed_packages=()
    uninstalled_packages=()
    skipped_packages=()
    failed_packages=()

    # Iterate over the package list and install each if missing
    for pkg in "${packages[@]}"; do
        func_install_if_missing "$pkg"
    done

    # Upgrade all installed Homebrew packages
    func_upgrade_packages

    # If any error occurred, exit with status 1 (triggers func_cleanup_exit)
    if $error ; then
        echo "Exiting due to errors."
        exit 1
    fi
fi

# Define the location of YAML
CONFIG_YAML_PATH="./config.yaml"

# Ensure config.yaml exists
if [[ ! -f "$CONFIG_YAML_PATH" ]]; then
    echo "config.yaml not found in the current directory." >&2
    exit 1  # Triggers func_cleanup_exit via EXIT trap
fi

# ------- Begin YAML Cleanup ------
# Assuming func_sed is a function defined in functions.sh for in-place sed operations
func_sed 's/([^\\])\\([^\\"])/\1\\\\\2/g' "$CONFIG_YAML_PATH"
func_sed 's/(^.*:[[:space:]]"[^\"]*)("[^"]*)(".*"$)/\1\\\2\\\3/g' "$CONFIG_YAML_PATH"

# Function to display the menu
display_menu() {
    cat <<EOF
Select your install type:

1) Minimal Install: This will provide the Homebrew basics, ignore packages in config.yaml, leaving the rest to you.
   ** You can also use this option to uninstall packages in config.yaml installed by option 2 by running the script again.

2) Advanced Install: Full setup includes packages in config.yaml
   ** Recommended if you want to get started with Neovim or install some of the great packages listed.

Enter selection:
EOF
}

[[ $DEBUG -eq 0 ]] && clear
while true; do
    display_menu
    read -r selection

    case "$selection" in
        1|2) break ;;
        *) echo "Invalid selection. Please enter 1 or 2."
           read -r -p "Press Enter to continue..." ;;
    esac
done

[[ $DEBUG -eq 0 ]] && clear

if [[ "$selection" -eq 2 && ! -f "$CONFIG_YAML_PATH" ]]; then
    echo "config.yaml not found in this directory." >&2
    exit 1  # Triggers func_cleanup_exit via EXIT trap
fi

if [[ $DARWIN -eq 0 ]] ; then

    # Retrieve DSM OS Version without Percentage Sign
    source /etc.defaults/VERSION
    clean_smallfix="${smallfixnumber%\%}"
    printf 'DSM Version: %s-%s Update %s\n' "$productversion" "$buildnumber" "$clean_smallfix"

    # Retrieve CPU Model Name
    echo -n "CPU: "
    awk -F': ' '/model name/ {print $2; exit}' /proc/cpuinfo

    # Retrieve System Architecture
    echo -n "Architecture: "
    uname -m
    echo

    # Derive the full version number as major.minor
    current_version=$(echo "$majorversion.$minorversion")
    required_version="7.2"

    # Convert the major and minor versions into a comparable number (e.g., 7.2 -> 702, 8.1 -> 801)
    current_version=$((majorversion * 100 + minorversion))
    required_version=$((7 * 100 + 2))

    # Compare the versions as integers
    if [ "$current_version" -lt "$required_version" ]; then
        echo "Your DSM version does not meet minimum requirements. DSM 7.2 is required."
        exit 1
    fi

    echo "Starting $( [[ "$selection" -eq 1 ]] && echo 'Minimal Install' || echo 'Full Setup' )..."

    export HOMEBREW_NO_ENV_HINTS=1
    export HOMEBREW_NO_AUTO_UPDATE=1

    # Install ldd file script
    sudo install -m 755 /dev/stdin /usr/bin/ldd <<EOF
#!/bin/bash
[[ \$(/usr/lib/libc.so.6) =~ version\ ([0-9]\.[0-9]+) ]] && echo "ldd \${BASH_REMATCH[1]}"
EOF

    # Install os-release file script
    sudo install -m 755 /dev/stdin /etc/os-release <<EOF
#!/bin/bash
echo "PRETTY_NAME=\"\$(source /etc.defaults/VERSION && printf '%s %s-%s Update %s' "\$os_name" "\$productversion" "\$buildnumber" "\$smallfixnumber")\""
EOF

    # Set a home for Homebrew
    if [[ ! -d /home ]]; then
        sudo mkdir -p /home
        sudo mount -o bind "/volume1/homes" /home
        sudo chown -R "$(whoami)":root /home
    fi

fi # closes DARWIN == 0

# Begin Homebrew install and package management
if [[ $DARWIN -eq 0 ]]; then
    # Already handled above for DARWIN=0
    :
elif [[ $DARWIN -eq 1 ]]; then
    echo "Starting Homebrew setup for macOS (DARWIN=1)..."

    # Install Homebrew if necessary
    func_install_homebrew

    # Initialize Homebrew
    func_initialize_homebrew

    # Define package lists based on DARWIN
    func_define_package_lists

    # Initialize arrays for summary
    installed_packages=()
    uninstalled_packages=()
    skipped_packages=()
    failed_packages=()

    # Iterate over the package list and install each if missing
    for pkg in "${packages[@]}"; do
        func_install_if_missing "$pkg"
    done

    # Upgrade all installed Homebrew packages
    func_upgrade_packages

    # Create a new .zprofile with Homebrew paths
    profile_template_path="./profile-templates/macos-profile-template"
    if [[ -f "$profile_template_path" ]]; then
        profile_filled=$(<"$profile_template_path")
        profile_filled="${profile_filled//\$HOMEBREW_PATH/$HOMEBREW_PATH}"
        echo "$profile_filled" > ~/.zprofile
        source ~/.zprofile
    else
        echo "Profile template '$profile_template_path' not found. Skipping .zprofile update." >&2
    fi
fi # end DARWIN ==1

echo "--------------------------PATH SET-------------------------------"
echo "$PATH"
echo "-----------------------------------------------------------------"

# Validate the YAML content directly from the file
if ! yq eval '.' "$CONFIG_YAML_PATH" > /dev/null 2>&1; then
    printf "Error: The YAML file '%s' is invalid.\n" "$CONFIG_YAML_PATH" >&2
    exit 1
else
    printf "The YAML file '%s' is valid.\n" "$CONFIG_YAML_PATH"
fi

# Read the content of YAML into the CONFIG_YAML variable
CONFIG_YAML=$(<"$CONFIG_YAML_PATH")

if [[ "$selection" -eq 1 ]]; then
    # Modify the action field with the value "uninstall" in temp variable CONFIG_YAML for .packages and .plugins
    CONFIG_YAML=$(printf '%s\n' "$CONFIG_YAML" | yq -e '
      .packages |= map_values(.action = "uninstall") |
      .plugins |= map_values(.action = "uninstall")
    ')
fi

if [[ $DARWIN -eq 0 ]] ; then
    # Check if Ruby is properly linked via Homebrew
    ruby_path=$(command -v ruby)
    if [[ "$ruby_path" != *"linuxbrew"* ]]; then
        echo "ruby is not linked via Homebrew. Linking ruby..."
        "$HOMEBREW_PATH"/brew link --overwrite ruby
        if [[ $? -eq 0 ]]; then
            echo "ruby has been successfully linked via Homebrew."
        else
            echo "Failed to link ruby via Homebrew." >&2
            exit 1
        fi
    else
        echo "ruby is linked via Homebrew."
    fi
fi # end DARWIN == 0

# Arrays to store summary messages
installed_packages=()
uninstalled_packages=()
skipped_packages=()
failed_packages=()

# Function to extract the base package name (assuming no need for transformation)
get_base_package() {
    local full_package="$1"
    # If package names include paths, extract the basename
    # Example: "homebrew/core/git" -> "git"
    local base_package
    base_package=$(basename "$full_package")
    echo "$base_package"
}

# Function to check install status and take action
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

# Function to install Zsh plugins
install_zsh_plugins() {
    echo "Installing Zsh plugins..."
    local plugins=()
    while IFS= read -r plugin; do
        plugins+=("$plugin")
    done < <(yq eval -r '.plugins | to_entries[] | select(.value.action == "install") | .key' <<< "$CONFIG_YAML")

    for plugin in "${plugins[@]}"; do
        local plugin_url
        local plugin_dir
        plugin_url=$(yq eval -r ".plugins[\"$plugin\"].url" <<< "$CONFIG_YAML")
        plugin_dir=$(yq eval -r ".plugins[\"$plugin\"].directory" <<< "$CONFIG_YAML")
        plugin_dir=${plugin_dir/#\~/$HOME}

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

# Function to uninstall Zsh plugins
uninstall_zsh_plugins() {
    echo "Uninstalling Zsh plugins..."
    local plugins=()
    while IFS= read -r plugin; do
        plugins+=("$plugin")
    done < <(yq eval -r '.plugins | to_entries[] | select(.value.action == "uninstall") | .key' <<< "$CONFIG_YAML")

    for plugin in "${plugins[@]}"; do
        local plugin_dir
        plugin_dir=$(yq eval -r ".plugins[\"$plugin\"].directory" <<< "$CONFIG_YAML")
        plugin_dir=${plugin_dir/#\~/$HOME}

        if [[ -d "$plugin_dir" ]]; then
            echo "🗑️ Uninstalling plugin: $plugin"
            rm -rf "$plugin_dir" && echo "✅ Successfully removed $plugin" || { echo "❌ Failed to remove $plugin"; failed_packages+=("$plugin"); }
        else
            echo "ℹ️ Plugin directory $plugin_dir does not exist. Skipping removal."
            skipped_packages+=("$plugin")
        fi
    done

    # Update ~/.zshrc to remove uninstalled plugins
    local default_plugins=("git" "web-search")
    local updated_plugins=("${default_plugins[@]}")
    while IFS= read -r plugin; do
        updated_plugins+=("$plugin")
    done < <(yq eval -r '.plugins | to_entries[] | select(.value.action == "install") | .key' <<< "$CONFIG_YAML")

    local plugins_list
    plugins_list=$(printf " %s" "${updated_plugins[@]}")
    plugins_list=${plugins_list:1} # Remove leading space
    func_sed "s|^plugins=.*$|plugins=($plugins_list)|" ~/.zshrc
}

# Function to install Zsh themes
install_zsh_themes() {
    echo "Installing Zsh themes..."
    local themes=()
    while IFS= read -r theme; do
        themes+=("$theme")
    done < <(yq eval -r '.themes | to_entries[] | select(.value.action == "install") | .key' <<< "$CONFIG_YAML")

    for theme in "${themes[@]}"; do
        local theme_url
        local theme_dir
        theme_url=$(yq eval -r ".themes[\"$theme\"].url" <<< "$CONFIG_YAML")
        theme_dir=$(yq eval -r ".themes[\"$theme\"].directory" <<< "$CONFIG_YAML")
        theme_dir=${theme_dir/#\~/$HOME}

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

# Function to uninstall Zsh themes
uninstall_zsh_themes() {
    echo "Uninstalling Zsh themes..."
    local themes=()
    while IFS= read -r theme; do
        themes+=("$theme")
    done < <(yq eval -r '.themes | to_entries[] | select(.value.action == "uninstall") | .key' <<< "$CONFIG_YAML")

    for theme in "${themes[@]}"; do
        local theme_dir
        theme_dir=$(yq eval -r ".themes[\"$theme\"].directory" <<< "$CONFIG_YAML")
        theme_dir=${theme_dir/#\~/$HOME}

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

# Main execution block
main() {
    # Ensure yq is installed
    if ! command -v yq &> /dev/null; then
        echo -e "${RED}yq is not installed. Please install yq to proceed.${NC}"
        exit 1
    fi

    # Initialize arrays
    packages_array=()
    actions_array=()

    # Populate packages_array and actions_array
    while IFS= read -r package; do
        packages_array+=("$package")
        # Extract the action for each package
        action=$(yq eval -r ".packages[\"$package\"].action" <<< "$CONFIG_YAML")
        actions_array+=("$action")
    done < <(yq eval -r '.packages | keys | .[]' <<< "$CONFIG_YAML")

    # Check if any packages were found
    if [ ${#packages_array[@]} -eq 0 ]; then
        echo -e "${YELLOW}No packages found in config.yaml.${NC}"
        exit 0
    fi

    # Loop over each package in the array
    for idx in "${!packages_array[@]}"; do
        package="${packages_array[$idx]}"
        action="${actions_array[$idx]}"
        process_package "$package" "$action"
    done

    # Install or uninstall Zsh plugins
    local plugins_action
    plugins_action=$(yq eval -r '.plugins | to_entries[] | .value.action' <<< "$CONFIG_YAML" | sort | uniq)

    if [[ "$plugins_action" == "install" ]]; then
        install_zsh_plugins
    elif [[ "$plugins_action" == "uninstall" ]]; then
        uninstall_zsh_plugins
    fi

    # Install or uninstall Zsh themes
    local themes_action
    themes_action=$(yq eval -r '.themes | to_entries[] | .value.action' <<< "$CONFIG_YAML" | sort | uniq)

    if [[ "$themes_action" == "install" ]]; then
        install_zsh_themes
    elif [[ "$themes_action" == "uninstall" ]]; then
        uninstall_zsh_themes
    fi

    # Read YAML and install/uninstall plugins
    yq eval -r '.plugins | to_entries[] | "\(.key) \(.value.action) \(.value.directory) \(.value.url)"' <<< "$CONFIG_YAML" | while read -r plugin action directory url; do
        # Expand the tilde (~) manually if it's present
        directory=${directory/#\~/$HOME}
        if [[ "$action" == "install" && ! -d "$directory" ]]; then
            echo "$plugin is not installed, cloning..."
            git clone "$url" "$directory"
        elif [[ "$action" == "install" && -d "$directory" ]]; then
            echo "$plugin is already installed."
        elif [[ "$action" == "uninstall" && -d "$directory" ]]; then
            echo "$plugin action is set to uninstall in config.yaml. Removing plugin directory..."
            rm -rf "$directory"
        elif [[ "$action" == "uninstall" && ! -d "$directory" ]]; then
            echo "$plugin is set to uninstall and is not installed. No action needed."
        elif [[ "$action" == "skip" ]]; then
            echo "$plugin action is set to skip in config.yaml. No action will be taken."
        else
            echo "Invalid action for $plugin in config.yaml. No action will be taken."
        fi
    done

    # Print summary
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

# Execute main function
main

# Create the symlinks
sudo ln -sf "$HOMEBREW_PATH"/python3 "$HOMEBREW_PATH"/python
sudo ln -sf "$HOMEBREW_PATH"/pip3 "$HOMEBREW_PATH"/pip
[[ $DARWIN -eq 0 ]] && sudo ln -sf "$HOMEBREW_PATH"/gcc "$HOMEBREW_PATH"/cc
[[ $DARWIN -eq 0 ]] && sudo ln -sf "$HOMEBREW_PATH"/zsh /bin/zsh
printf "\nFinished creating symlinks"

# Enable perl in Homebrew
if [[ $(yq eval -r '.packages.perl.action' <<< "$CONFIG_YAML") == "install" ]]; then
    if [[ $DARWIN -eq 0 ]] ; then
        printf "\nFixing perl symlink..."
        # Create symlink to Homebrew's Perl in /usr/bin
        sudo ln -sf "$HOMEBREW_PATH"/perl /usr/bin/perl
        # TODO: CHECK IF MACOS NEOVIM IS USING HOMEBREW PERL. ONE OF THE NVIM PLUGINS IS HARD CODED TO /usr/bin/perl
    fi

    printf "\nSetting up permissions for perl environment..."
    # Ensure permissions on perl5 and .cpan directories before any creation
    sudo mkdir -p "$HOME/perl5" "$HOME/.cpan"
    sudo chown -R "$(whoami)":$DEFAULT_GROUP "$HOME/perl5" "$HOME/.cpan"
    sudo chmod -R 775 "$HOME/perl5" "$HOME/.cpan"

    printf "\nEnabling perl cpan with defaults and permission fix"
    # Configure CPAN to install local::lib in $HOME/perl5 with default settings
    PERL_MM_USE_DEFAULT=1 PERL_MM_OPT=INSTALL_BASE=$HOME/perl5 cpan local::lib

    # Re-run local::lib setup to ensure environment is correctly configured
    eval "$(perl -I"$HOME/perl5/lib/perl5" -Mlocal::lib="$HOME/perl5")"

    # Now make sure local::lib is set up properly in CPAN
    cpan local::lib
fi

# oh-my-zsh will always be installed with the latest version
[[ -e ~/.oh-my-zsh ]] && rm -rf ~/.oh-my-zsh
if [[ -x $(command -v zsh) ]]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    chmod -R 755 ~/.oh-my-zsh
fi

# Check if additional Neovim packages should be installed
echo "-----------------------------------------------------------------"
if [[ $(yq eval -r '.packages.neovim.action' <<< "$CONFIG_YAML") == "install" ]]; then
    echo "Calling ./install-neovim.sh for additional setup packages"
    # Create a temporary file to store YAML data
    temp_file=$(mktemp)
    printf '%s\n' "$CONFIG_YAML" > "$temp_file"

    bash "./install-neovim.sh" "$temp_file"
    CONFIG_YAML=$(<"$temp_file")
    rm "$temp_file"
else
    echo "SKIPPING: Neovim components as config.yaml install flag is set to false."
fi

# Extract and filter alias commands directly from CONFIG_YAML
alias_commands=$(yq eval -r '
  (.packages + .plugins + .themes)
  | to_entries[]
  | select(.value.aliases != [] and .value.action != "uninstall")
  | .value.aliases
  | to_entries[]
  | select(.key != "" and .value != "")
  | "\(.key)=\(.value)"
' <<< "$CONFIG_YAML")

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
  (.packages + .plugins + .themes)
  | to_entries[]
  | select(.value.eval != [] and .value.action == "install")
  | .value.eval[]
' <<< "$CONFIG_YAML")

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

# Finalize with zsh execution in Synology ash ~/.profile
if [[ $DARWIN -eq 0 ]] ; then
    command_to_add='[[ -x $HOMEBREW_PATH/bin/zsh ]] && exec $HOMEBREW_PATH/bin/zsh'
    if ! grep -xF "$command_to_add" ~/.profile; then
        echo "$command_to_add" >> ~/.profile
    fi

    if [[ "$git_install_flag" ]]; then
        sudo synopkg uninstall Git > /dev/null 2>&1
    fi

    # Check if Perl is installed via Synology Package Center
    if synopkg list | grep -q "Perl"; then
        echo ""
        echo "#############################################################"
        echo "#                                                           #"
        echo "#   Perl is installed via the Synology Package Center.      #"
        echo "#   It is recommended that you uninstall this version.      #"
        echo "#   The Homebrew version will be used instead.              #"
        echo "#                                                           #"
        echo "#############################################################"
        echo ""
    fi
fi # end DARWIN == 0

echo "Script completed successfully. You will now be transported to ZSH!!!"
exec zsh --login


