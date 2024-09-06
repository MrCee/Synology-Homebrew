#!/bin/bash

DEBUG=0
[[ $DEBUG == 1 ]] && echo "DEBUG mode"

SCRIPT_PATH=$(realpath "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")

# Change to the script directory
cd "$SCRIPT_DIR" || { echo "Failed to change directory to $SCRIPT_DIR" >&2; exit 1; }
echo "Working directory: $SCRIPT_DIR"

# Source the functions file
source "$SCRIPT_DIR/functions.sh"

# login and cache sudo which creates a sudoers file
func_sudoers

if [[ $(uname) == "Darwin" ]]; then
    echo "This script is for Synology NAS. Do not run it from macOS. Exiting." >&2
    exit 1
fi

# Check if the script is being run as root
if [[ "$EUID" -eq 0 ]]; then
    echo "This script should not be run as root. Run it as a regular user, although we will need root password in a second..." >&2
    exit 1
fi

# Check prerequisites of this script
error=false

# Check if Synology Homes is enabled
if [[ ! -d /var/services/homes/$(whoami) ]]; then
    echo "Synology Homes has NOT been enabled. Please enable in DSM Control Panel >> Users & Groups >> Advanced >> User Home." >&2
    error=true
fi

# Check if Homebrew is installed
if [[ ! -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    echo "Homebrew is not installed. Checking environment for requirements..."
    
    # Check if Git is installed
    if ! command -v git > /dev/null; then
        echo "Git not installed. Please install Git via package manager before running." >&2
        error=true
    else
        echo "Git has been found"
    fi
else
    echo "Homebrew is installed. Checking your environment to see if further actions are required. Please wait..."
fi

# If any error occurred, exit with status 1
if $error; then
    exit 1
fi

# Define the location of YAML
CONFIG_YAML_PATH="$SCRIPT_DIR/config.yaml"

# Ensure config.yaml exists
if [[ ! -f "$CONFIG_YAML_PATH" ]]; then
    echo "config.yaml not found in $SCRIPT_DIR"
    exit 1
fi

# ------- Begin YAML Cleanup ------
func_sed 's/([^\\])\\([^\\"])/\1\\\\\2/g' "$CONFIG_YAML_PATH"
func_sed 's/(^.*:[[:space:]]"[^\"]*)("[^"]*)(".*"$)/\1\\\2\\\3/g' "$CONFIG_YAML_PATH"
func_sed 's/install: skip/install: \"skip\"/g' "$CONFIG_YAML_PATH"
func_sed 's/install: true/install: \"true\"/g' "$CONFIG_YAML_PATH"
func_sed 's/install: false/install: \"false\"/g' "$CONFIG_YAML_PATH"

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

# Create a new .profile and add homebrew paths
cat > "$HOME/.profile" <<EOF
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/syno/sbin:/usr/syno/bin:/usr/local/sbin:/usr/local/bin
# Directories to add to PATH
directories=(
  "/home/linuxbrew/.linuxbrew/lib/ruby/gems/3.3.0/bin"
  "/home/linuxbrew/.linuxbrew/opt/glibc/sbin"
  "/home/linuxbrew/.linuxbrew/opt/glibc/bin"
  "/home/linuxbrew/.linuxbrew/opt/binutils/bin"
  "/home/linuxbrew/.linuxbrew/sbin"
  "/home/linuxbrew/.linuxbrew/bin"
)
# Iterate over each directory in the 'directories' array
for dir in "\${directories[@]}"; do
    # Check if the directory is already in PATH
    if [[ ":\$PATH:" != *":\$dir:"* ]]; then
        # If not found, append it to PATH
        export PATH="\$dir:\$PATH"
    fi
done

# Additional environment variables
export LDFLAGS="-L/home/linuxbrew/.linuxbrew/opt/glibc/lib"
export CPPFLAGS="-I/home/linuxbrew/.linuxbrew/opt/glibc/include"
export XDG_CONFIG_HOME="\$HOME/.config"
export HOMEBREW_GIT_PATH=/home/linuxbrew/.linuxbrew/bin/git

# Keep gcc up to date. Find the latest version of gcc installed and set symbolic links from version 11 onwards
max_version=\$(/bin/ls -d /home/linuxbrew/.linuxbrew/opt/gcc/bin/gcc-* | grep -oE '[0-9]+$' | sort -nr | head -n1)
# Create symbolic link for gcc to latest gcc-*
ln -sf "/home/linuxbrew/.linuxbrew/bin/gcc-\$max_version" "/home/linuxbrew/.linuxbrew/bin/gcc"
# Create symbolic links for gcc-11 to max_version pointing to latest gcc-*
for ((i = 11; i < max_version; i++)); do
    ln -sf "/home/linuxbrew/.linuxbrew/bin/gcc-\$max_version" "/home/linuxbrew/.linuxbrew/bin/gcc-\$i"
done

eval "\$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

# fzf-git.sh source git key bindings for fzf-git
[[ -f \$HOME/.scripts/fzf-git.sh ]] && source "\$HOME/.scripts/fzf-git.sh"

if [[ -x \$(command -v perl) && \$(perl -Mlocal::lib -e '1' 2>/dev/null) ]]; then
    eval "\$(perl -I\$HOME/perl5/lib/perl5 -Mlocal::lib=\$HOME/perl5 2>/dev/null)"
fi
EOF

# Begin Homebrew install. Remove brew git env if it does not exist
[[ ! -x /home/linuxbrew/.linuxbrew/bin/git ]] && unset HOMEBREW_GIT_PATH
NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" 2> /dev/null
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
ulimit -n 2048
brew install --quiet glibc gcc 2> /dev/null
brew install --quiet git 2> /dev/null
brew install --quiet ruby 2> /dev/null
brew install --quiet clang-build-analyzer 2> /dev/null
brew install --quiet zsh 2> /dev/null
brew install --quiet yq 2> /dev/null
brew upgrade --quiet 2> /dev/null
source ~/.profile

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
    # Modify the install field within each entry in .packages and .plugins
    CONFIG_YAML=$(printf '%s\n' "$CONFIG_YAML" | yq -e '
      .packages |= map_values(.install = "false") |
      .plugins |= map_values(.install = "false")
    ')
fi

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

# Create a brew list of installed packages into an array
BREW_LIST_ARRAY=($(brew list -1))

# Read YAML and process packages
yq eval -r '.packages | to_entries[] | .key' <<< "$CONFIG_YAML" | while IFS= read -r package; do
    install_status=$(yq eval -r ".packages[\"$package\"].install" <<< "$CONFIG_YAML")
    base_package=$(basename "$package")

    if [[ " ${BREW_LIST_ARRAY[*]} " =~ " ${base_package} " ]]; then
        action="already installed"
        if [[ "$install_status" == "false" ]]; then
            action="flag is set to uninstall"
            brew uninstall --quiet "$package"
        elif [[ "$install_status" == "skip" ]]; then
            action="flag is set to skip"
        fi
    else
        action="not installed"
        if [[ "$install_status" == "true" ]]; then
            action="installing"
            brew install --quiet "$package"
        elif [[ "$install_status" == "false" || "$install_status" == "skip" ]]; then
            action="flag is set to $install_status"
        fi
    fi

    if [[ "$install_status" != "true" && "$install_status" != "false" && "$install_status" != "skip" ]]; then
        action="invalid install status"
    fi

    echo "$package is $action."
done

# Create the symlinks
echo "Creating symlinks"
sudo ln -sf /home/linuxbrew/.linuxbrew/bin/python3 /home/linuxbrew/.linuxbrew/bin/python
sudo ln -sf /home/linuxbrew/.linuxbrew/bin/pip3 /home/linuxbrew/.linuxbrew/bin/pip
sudo ln -sf /home/linuxbrew/.linuxbrew/bin/gcc /home/linuxbrew/.linuxbrew/bin/cc
sudo ln -sf /home/linuxbrew/.linuxbrew/bin/zsh /bin/zsh
echo "Finished creating symlinks"

# Enable perl in homebrew
if [[ $(printf '%s\n' "$CONFIG_YAML" | yq eval -r '.packages.perl.install') == "true" ]]; then
    echo "Fixing perl symlink..."
    # Create symlink to Homebrew's Perl in /usr/bin
    sudo ln -sf /home/linuxbrew/.linuxbrew/bin/perl /usr/bin/perl

    echo "Setting up permissions for perl environment..."
    # Ensure permissions on perl5 and .cpan directories before any creation
    sudo mkdir -p $HOME/perl5 $HOME/.cpan
    sudo chown -R "$(whoami)":root $HOME/perl5 $HOME/.cpan
    sudo chmod -R 775 $HOME/perl5 $HOME/.cpan

    echo "Enabling perl cpan with defaults and permission fix"
    # Configure CPAN to install local::lib in $HOME/perl5 with default settings
    sudo -E PERL_MM_USE_DEFAULT=1 PERL_MM_OPT=INSTALL_BASE=$HOME/perl5 cpan local::lib

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
if [[ $(printf '%s\n' "$CONFIG_YAML" | yq eval -r '.packages.neovim.install') == "true" ]]; then
    echo "Calling $SCRIPT_DIR/nvim_config.sh for additional setup packages"
    
    # Create a temporary file to store YAML data
    temp_file=$(mktemp)
    printf '%s\n' "$CONFIG_YAML" > "$temp_file"

    bash "$SCRIPT_DIR/nvim_config.sh" "$temp_file"
    CONFIG_YAML=$(<"$temp_file")
    rm "$temp_file"
else
    echo "SKIPPING: Neovim components as config.yaml install flag is set to false."
fi

# Read YAML and install/uninstall plugins
yq eval -r '.plugins | to_entries[] | "\(.key) \(.value.install) \(.value.directory) \(.value.url)"' <<< "$CONFIG_YAML" | while read -r plugin install directory url; do
    # Expand the tilde (~) manually if it's present
    directory=${directory/#\~/$HOME}
    if [[ "$install" == "true" && ! -d "$directory" ]]; then
        echo "$plugin is not installed, cloning..."
        git clone "$url" "$directory"
    elif [[ "$install" == "true" && -d "$directory" ]]; then
        echo "$plugin is already installed."
    elif [[ "$install" == "false" && -d "$directory" ]]; then
        echo "$plugin install flag is set to false in config.yaml. Removing plugin directory..."
        rm -rf "$directory"
    elif [[ "$install" == "false" && ! -d "$directory" ]]; then
        echo "$plugin flag is set to false and is not installed. No action needed."
    elif [[ "$install" == "skip" ]]; then
        echo "$plugin install flag is set to skip in config.yaml. No action will be taken."
    elif [[ "$install" == "handled" ]]; then
        echo "$plugin has already been handled by nvim_config.sh."
    else
        echo "Invalid install status for $plugin in config.yaml. No action will be taken."
    fi
done

# Check if any zsh packages should be configured
echo "-----------------------------------------------------------------"
echo "Calling $SCRIPT_DIR/zsh_config.sh for additional zsh configuration"
bash "$SCRIPT_DIR/zsh_config.sh" "$CONFIG_YAML"

# Extract and filter alias commands directly from CONFIG_YAML
alias_commands=$(yq eval -r '
  (.packages + .plugins)
  | to_entries[]
  | select(.value.aliases != [] and .value.install != "false")
  | .value.aliases
  | to_entries[]
  | select(.key != "" and .key != null and .value != "" and .value != null)
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
  | select(.value.eval != [] and .value.install != "false")
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
command_to_add='[[ -x /home/linuxbrew/.linuxbrew/bin/zsh ]] && exec /home/linuxbrew/.linuxbrew/bin/zsh'
if ! grep -xF "$command_to_add" ~/.profile; then
    echo "$command_to_add" >> ~/.profile
fi

# Finish script with cleanup and transport
sudo rm -rf "$SUDOERS_FILE"

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
echo "Script completed successfully. You will now be transported to ZSH!!!"
exec zsh --login
