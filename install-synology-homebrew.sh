#!/bin/bash

DEBUG=0
[[ $DEBUG == 1 ]] && echo "DEBUG mode on with strict -euo pipefail error handling" && set -euo pipefail

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

# Unified Cleanup Function for Handling Exits and Interruptions
# (Defined in functions.sh as func_cleanup_exit)

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

[[ $DEBUG == 1 ]] && echo "Debug: SUDOERS_FILE is set to '$SUDOERS_FILE'"

# Check if the script is being run as root
if [[ "$EUID" -eq 0 ]]; then
    echo "This script should not be run as root. Run it as a regular user, although we will need root password in a second..." >&2
    exit 1  # Triggers func_cleanup_exit via EXIT trap
fi

# Check prerequisites of this script
error=false
git_install_flag=false

if [[ $DARWIN == 0 ]]; then
    # Check if Synology Homes is enabled
    if [[ ! -d /var/services/homes/$(whoami) ]]; then
        echo "Synology Homes has NOT been enabled. Please enable in DSM Control Panel >> Users & Groups >> Advanced >> User Home." >&2
        error=true
    fi

    # Check if Homebrew is installed
    if [[ ! -x $HOMEBREW_PATH/bin/brew ]]; then
        echo "Homebrew is not installed. Checking environment for requirements..."

        # Check if Git is installed
        if ! git --version > /dev/null 2>&1; then
            echo "Git not installed. Adding the SynoCommunity repository..."

            # Add SynoCommunity feed if not present
            if [[ ! -f /usr/syno/etc/packages/feeds ]]; then
                echo "Adding SynoCommunity feed..."
                echo '[{"feed":"https://packages.synocommunity.com/","name":"SynoCommunity"}]' | sudo tee /usr/syno/etc/packages/feeds > /dev/null
                sudo chmod 755 /usr/syno/etc/packages/feeds
            fi

            # Append to feeds if SynoCommunity is missing
            if ! sudo grep -q "https://packages.synocommunity.com/" /usr/syno/etc/packages/feeds; then
                echo "Appending SynoCommunity feed..."
                echo '[{"feed":"https://packages.synocommunity.com/","name":"SynoCommunity"}]' | sudo tee -a /usr/syno/etc/packages/feeds > /dev/null
            fi

            # Attempt to install Git
            echo "Attempting to install Git..."
            sudo synopkg install_from_server Git
            git_install_flag=true

            # Confirm if Git was installed successfully
            if git --version > /dev/null 2>&1; then
                echo "Git has been installed"
            else
                echo "Git could not be installed. Please install it manually from SynoCommunity in Package Centre (https://packages.synocommunity.com)." >&2
                error=true
            fi
        else
            echo "Git is already installed."
        fi  # Closes 'if ! git --version'

    else
        echo "Homebrew is already installed."
    fi  # Closes 'if [[ ! -x $HOMEBREW_PATH/bin/brew ]]'

    # If any error occurred, exit with status 1 (triggers func_cleanup_exit)
    if $error ; then
        echo "Exiting due to errors."
        exit 1
    fi
fi # end $DARWIN

# Define the location of YAML
CONFIG_YAML_PATH="./config.yaml"

# Ensure config.yaml exists
if [[ ! -f "$CONFIG_YAML_PATH" ]]; then
    echo "config.yaml not found in ."
    exit 1  # Triggers func_cleanup_exit via EXIT trap
fi

# ------- Begin YAML Cleanup ------
func_sed 's/([^\\])\\([^\\"])/\1\\\\\2/g' "$CONFIG_YAML_PATH"
func_sed 's/(^.*:[[:space:]]"[^\"]*)("[^"]*)(".*"$)/\1\\\2\\\3/g' "$CONFIG_YAML_PATH"

# Function to display the menu
display_menu() {
    cat <<EOF
Select your install type:

1) Minimal Install: This will provide the homebrew basics, ignore packages in config.yaml, leaving the rest to you.
   ** You can also use this option to uninstall packages in config.yaml installed by option 2 by running the script again.

2) Advanced Install: Full setup includes packages in config.yaml
   ** Recommended if you want to get started with Neovim or install some of the great packages listed.

Enter selection:
EOF
}

[[ $DEBUG == 0 ]] && clear
while true; do
    display_menu
    read -r selection

    case "$selection" in
        1|2) break ;;
        *) echo "Invalid selection. Please enter 1 or 2."
           read -r -p "Press Enter to continue..." ;;
    esac
done

[[ $DEBUG == 0 ]] && clear

if [[ "$selection" -eq 2 && ! -f "$CONFIG_YAML_PATH" ]]; then
    echo "config.yaml not found in this directory" >&2
    exit 1  # Triggers func_cleanup_exit via EXIT trap
fi

if [[ $DARWIN == 0 ]] ; then

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
[[ \$("/usr/lib/libc.so.6") =~ version\ ([0-9]\.[0-9]+) ]] && echo "ldd \${BASH_REMATCH[1]}"
EOF

# Install os-release file script
sudo install -m 755 /dev/stdin /etc/os-release <<EOF
#!/bin/bash
echo "PRETTY_NAME=\"\$(source /etc.defaults/VERSION && printf '%s %s-%s Update %s' \"\$os_name\" \"\$productversion\" \"\$buildnumber\" \"\$smallfixnumber\")\""
EOF

# Set a home for homebrew
if [[ ! -d /home ]]; then
    sudo mkdir -p /home
    sudo mount -o bind "/volume1/homes" /home
    sudo chown -R "$(whoami)":root /home
fi



# Begin Homebrew install. Remove brew git env if it does not exist
[[ ! -x $HOMEBREW_PATH/bin/git ]] && unset HOMEBREW_GIT_PATH
if ! command -v brew >/dev/null 2>&1; then
NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" 2> /dev/null 2>&1 | sed '/==> Next steps:/,/^$/d'
else
    printf "brew command found. Please wait...\n"
fi
eval "$($HOMEBREW_PATH/bin/brew shellenv)"
ulimit -n 2048
brew install --quiet glibc gcc 2> /dev/null
brew install --quiet git 2> /dev/null
brew install --quiet ruby 2> /dev/null
brew install --quiet clang-build-analyzer 2> /dev/null
brew install --quiet zsh 2> /dev/null
brew install --quiet yq 2> /dev/null
brew upgrade --quiet 2> /dev/null


# Create a new .profile with homebrew paths
profile_filled=$(<./profiles/synology-profile-template)
profile_filled="${profile_filled//\$HOMEBREW_PATH/$HOMEBREW_PATH}"
echo "$profile_filled" > ~/.profile
source ~/.profile
fi # end DARWIN

if [[ $DARWIN == 1 ]] ; then
if ! command -v brew >/dev/null 2>&1; then
NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" 2> /dev/null 2>&1 | sed '/==> Next steps:/,/^$/d'
else
    printf "brew command found. Please wait...\n"
fi
eval "$($HOMEBREW_PATH/bin/brew shellenv)"
brew install --quiet git 2> /dev/null
brew install --quiet yq 2> /dev/null
brew install --quiet ruby 2> /dev/null
brew install --quiet python3 2> /dev/null
brew install --quiet coreutils 2> /dev/null
brew install --quiet findutils 2> /dev/null
brew install --quiet gnu-sed 2> /dev/null
brew install --quiet grep 2> /dev/null
brew install --quiet gawk 2> /dev/null

# Create a new .zprofile with homebrew paths
profile_filled=$(<./profiles/macos-profile-template)
profile_filled="${profile_filled//\$HOMEBREW_PATH/$HOMEBREW_PATH}"
echo "$profile_filled" > ~/.zprofile
source ~/.zprofile
fi # end DARWIN

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

if [[ $DARWIN == 0 ]] ; then
# Check if Ruby is properly linked via Homebrew
ruby_path=$(command -v ruby)
if [[ "$ruby_path" != *"linuxbrew"* ]]; then
    echo "ruby is not linked via Homebrew. Linking ruby..."
    brew link --overwrite ruby
    if [[ $? -eq 0 ]]; then
        echo "ruby has been successfully linked via Homebrew."
    else
        echo "Failed to link ruby via Homebrew." >&2
        exit 1
    fi
else
    echo "ruby is linked via Homebrew."
fi
fi # end DARWIN

# Arrays to store summary messages
installed_packages=()
uninstalled_packages=()
skipped_packages=()
failed_packages=()

# Define color codes (optional for enhanced readability)
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to extract the base package name
get_base_package() {
    local full_package="$1"
    # Extract the text after the last slash
    local base_package="${full_package##*/}"
    echo "$base_package"
}

# Function to check install status and take action
process_package() {
    local package="$1"
    local action="$2"
    local base_package
    base_package=$(get_base_package "$package")

    # Check if the package is already installed
    if brew list --formula -1 | grep -Fxq "$base_package"; then
        case "$action" in
            uninstall)
                echo -e "🔄 ${YELLOW}${base_package}${NC}: Uninstalling..."
                if brew uninstall --quiet "$base_package"; then
                    uninstalled_packages+=("$base_package")
                else
                    echo -e "${RED}❌ Failed to uninstall ${base_package}.${NC}"
                    failed_packages+=("$base_package (uninstall)")
                fi
                ;;
            skip)
                echo -e "⏭️ ${YELLOW}${base_package}${NC}: Skipping (flagged to skip)"
                skipped_packages+=("$base_package")
                ;;
            install)
                echo -e "${GREEN}✅ ${base_package}${NC}: Already installed"
                ;;
            *)
                echo -e "${RED}⚠️ ${base_package}${NC}: Invalid action ('${action}')"
                failed_packages+=("$base_package (invalid action)")
                ;;
        esac
    else
        case "$action" in
            install)
                echo -e "🛠️ ${GREEN}${base_package}${NC}: Installing..."
                if brew install --quiet "$base_package" 2>&1 | sed '/==> Next steps:/,/^$/d; /By default/d'; then
                    installed_packages+=("$base_package")
                else
                    echo -e "${RED}❌ Error installing ${base_package}.${NC}"
                    failed_packages+=("$base_package (install)")
                fi
                ;;
            uninstall)
                echo -e "🚫 ${YELLOW}${base_package}${NC}: Not installed but flagged for uninstall"
                skipped_packages+=("$base_package")
                ;;
            skip)
                echo -e "⏭️ ${YELLOW}${base_package}${NC}: Skipping (flagged to skip)"
                skipped_packages+=("$base_package")
                ;;
            *)
                echo -e "${RED}⚠️ ${base_package}${NC}: Invalid action ('${action}')"
                failed_packages+=("$base_package (invalid action)")
                ;;
        esac
    fi
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

    # Print summary
    echo -e "\n📋 ${GREEN}Summary:${NC}"

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
# printf "\nCreating symlinks"
sudo ln -sf $HOMEBREW_PATH/bin/python3 $HOMEBREW_PATH/bin/python
sudo ln -sf $HOMEBREW_PATH/bin/pip3 $HOMEBREW_PATH/bin/pip
[[ $DARWIN == 0 ]] && sudo ln -sf $HOMEBREW_PATH/bin/gcc $HOMEBREW_PATH/bin/cc
[[ $DARWIN == 0 ]] && sudo ln -sf $HOMEBREW_PATH/bin/zsh /bin/zsh
printf "\nFinished creating symlinks"

# Enable perl in homebrew
if [[ $(yq eval -r '.packages.perl.action' <<< "$CONFIG_YAML") == "install" ]]; then
if [[ $DARWIN == 0 ]] ; then
            printf "\nFixing perl symlink..."
            # Create symlink to Homebrew's Perl in /usr/bin
            sudo ln -sf $HOMEBREW_PATH/bin/perl /usr/bin/perl
            # TODO: CHECK IF MACOS NEOVIM IS USING HOMEBREW PERL. ONE OF THE NVIM PLUGINS IS HARD CODED TO /usr/bin/perl
    fi

    printf "\nSetting up permissions for perl environment..."
    # Ensure permissions on perl5 and .cpan directories before any creation
    sudo mkdir -p $HOME/perl5 $HOME/.cpan
    sudo chown -R "$(whoami)":$DEFAULT_GROUP $HOME/perl5 $HOME/.cpan
    sudo chmod -R 775 $HOME/perl5 $HOME/.cpan


    printf "\nEnabling perl cpan with defaults and permission fix"
    # Configure CPAN to install local::lib in $HOME/perl5 with default settings
    PERL_MM_USE_DEFAULT=1 PERL_MM_OPT=INSTALL_BASE=$HOME/perl5 cpan local::lib

    # Re-run local::lib setup to ensure environment is correctly configured
    eval $(perl -I$HOME/perl5/lib/perl5 -Mlocal::lib=$HOME/perl5)

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

# Check if any zsh packages should be configured
echo "-----------------------------------------------------------------"
echo "Calling ./zsh_config.sh for additional zsh configuration"
bash "./zsh_config.sh" "$CONFIG_YAML"

# Extract and filter alias commands directly from CONFIG_YAML
alias_commands=$(yq eval -r '
  (.packages + .plugins)
  | to_entries[]
  | select(.value.aliases != [] and .value.action != "uninstall")
  | .value.aliases
  | to_entries[]
  | select(.key != "" and .value != "")
  | "alias \(.key)=\(.value)"
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

# Finalize with zsh execution in Synology ash ~/.profile
if [[ $DARWIN == 0 ]] ; then
command_to_add='[[ -x $HOMEBREW_PATH/bin/zsh ]] && exec $HOMEBREW_PATH/bin/zsh'
if ! grep -xF "$command_to_add" ~/.profile; then
    echo "$command_to_add" >> ~/.profile
fi

if [[ "$git_install_flag" ]] ; then
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
fi # end DARWIN

func_cleanup_exit 0
echo "Script completed successfully. You will now be transported to ZSH!!!"
exec zsh --login
