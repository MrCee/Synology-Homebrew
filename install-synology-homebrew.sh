#!/bin/bash

# Cache sudo credentials
sudo -k
sudo -v || { echo "Failed to cache sudo credentials"; exit 1; }

SCRIPT_PATH=$(realpath "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")

# Change to the script directory
cd "$SCRIPT_DIR" || { echo "Failed to change directory to $SCRIPT_DIR"; exit 1; }
echo "Working directory: $SCRIPT_DIR"

# Define the sudoers file
SUDOERS_FILE="/etc/sudoers.d/custom_homebrew_sudoers"
sudo rm -f $SUDOERS_FILE 
CURRENT_USER=$(whoami)

# Function to clean up and exit the script
cleanup() {
    echo "Cleaning up..."
    sudo rm -f "$SUDOERS_FILE"
    exit 1  # Exit the script with a status code of 1
}

# Set traps for various signals
trap cleanup INT TERM HUP QUIT ABRT ALRM PIPE

# Create the sudoers file
cat <<EOF | sudo tee $SUDOERS_FILE > /dev/null
Defaults syslog=authpriv
root ALL=(ALL) ALL
$CURRENT_USER ALL=NOPASSWD: ALL
EOF

# Set permissions on the sudoers file
sudo chmod 0440 $SUDOERS_FILE || { echo "Failed to set permissions on sudoers file"; exit 1; }

[[ $(uname) == "Darwin" ]] && echo "This script is for Synology NAS. You don't run this from macOS. Script will now exit" && exit 1

DEBUG=0
[[ $DEBUG == 1 ]] && echo "DEBUG mode"

# Check if the script is being run as root
if [ "$EUID" -eq 0 ]; then
    echo "This script should not be run as root. Please run it as a regular user, although we will need root password in a second..."
    exit 1
fi

# Check prerquisites of this script
error=false

# Check if Synology Homes is enabled
if [[ ! -d /var/services/homes/$(whoami) ]]; then
    echo "Synology Homes has NOT been enabled. Please enable in DSM Control Panel >> Users & Groups >> Advanced >> User Home."
    error=true
fi

# Check if Homebrew is installed
if [[ ! -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    echo "Homebrew is not installed. Checking environment for requirements..."

 # Check if Git is installed
    if [[ ! -x $(command -v git) ]]; then
        echo "Git not installed. Please install Git via package manager before running."
        error=true
    else
	echo "Git has been found"
    fi
else
	echo "Homebrew is installed. Checking your environment to see if further actions are required. Please wait..."
fi

# If any error occurred, exit with status 1
if $error; then
    exit 0
fi

# Define the location of JSON
CONFIG_JSON_PATH="$SCRIPT_DIR/config.json"

# Ensure config.json exists
if [[ ! -f "$CONFIG_JSON_PATH" ]]; then
    echo "config.json not found in $SCRIPT_DIR"
    exit 1
fi

# Source the functions file
source "$SCRIPT_DIR/functions.sh"

# Format JSON to ensure compatibility
func_sed 's/([^\\])\\([^\\"])/\1\\\\\2/g' "$CONFIG_JSON_PATH"
func_sed 's/(^.*:[[:space:]]*\"[^\\]*)(\".*)(\".*\"$)/\1\\\2\\\3/g' "$CONFIG_JSON_PATH"
func_sed 's/"install": skip/"install": "skip"/' "$CONFIG_JSON_PATH"
func_sed 's/"install": "true"/"install": true/' "$CONFIG_JSON_PATH"
func_sed 's/"install": "false"/"install": false/' "$CONFIG_JSON_PATH"

# Update plugin keys and overwrite config.json
temp_file=$(mktemp)
if ! jq '{
  packages: .packages,
  plugins: (.plugins | to_entries | map({key: (.value.url | split("/")[-1]), value: .value}) | from_entries)
}' "$CONFIG_JSON_PATH" > "$temp_file"; then
    echo "Failed to process JSON with jq."
    rm "$temp_file"
    exit 1
else
    # Replace the original config.json with the updated version
    mv "$temp_file" "$CONFIG_JSON_PATH"
    echo "config.json has been updated successfully."

    # Validate JSON
    if ! jq empty "$CONFIG_JSON_PATH" > /dev/null 2>&1; then
        echo "Invalid JSON."
        exit 1
    else
        echo "JSON is valid."
    fi
fi

# Read the content of JSON into the CONFIG_JSON variable
CONFIG_JSON=$(<"$CONFIG_JSON_PATH")

# Function to display the menu
display_menu() {
    cat <<EOF
Select your install type:

1) Minimal Install: This will provide the homebrew basics, ignore packages in config.json, leaving the rest to you.
   ** You can also use this option to uninstall packages in config.json installed by option 2 by running the script again.

2) Advanced Install: Full setup includes packages in config.json
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
           read -r -p "Press Enter to continue..."
           ;;
    esac
done

[[ $DEBUG == 0 ]] && clear
display_info "$selection"

if [[ "$selection" -eq 2 && ! -f "$CONFIG_JSON_PATH" ]]; then
    echo "config.json not found in this directory"
    exit 1
fi

echo "Starting $( [[ "$selection" -eq 1 ]] && echo 'Minimal Install' || echo 'Full Setup' )..."

if [[ "$selection" -eq 1 ]]; then
    # Update install fields to false
    CONFIG_JSON=$(jq '.packages |= with_entries(.value.install = false)' <<< "$CONFIG_JSON")
fi

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
echo "PRETTY_NAME=\"\$(source /etc.defaults/VERSION && echo \${os_name} \${productversion}-\${buildnumber} Update \${smallfixnumber})\""
EOF

# Set a home for homebrew
if [[ ! -d /home ]]; then
    sudo bash -c '[[ ! -d /home ]] && sudo mkdir /home && sudo mount -o bind "/volume1/homes" /home'
    sudo chown -R $(whoami):root /home
fi

# Create a new .profile and add homebrew paths
cat > ~/.profile <<EOF
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
export XDG_CONFIG_HOME="\$HOME"/.config
export HOMEBREW_GIT_PATH=/home/linuxbrew/.linuxbrew/bin/git

# Keep gcc up to date. Find the latest version of gcc installed and set symbolic links
# Extract the version number from latest gcc
max_version=\$(ls -d /home/linuxbrew/.linuxbrew/opt/gcc/bin/gcc-* | grep -oE '[0-9]+$' | sort -nr | head -n1)
# Create symbolic link for gcc to latest gcc-* 
ln -sf "/home/linuxbrew/.linuxbrew/bin/gcc-\$max_version" "/home/linuxbrew/.linuxbrew/bin/gcc"
# Create symbolic links for gcc-11 to max_version-1 pointing to latest gcc-*
for ((i = 11; i < max_version; i++)); do
    ln -sf "/home/linuxbrew/.linuxbrew/bin/gcc-\$max_version" "/home/linuxbrew/.linuxbrew/bin/gcc-\$i"
done

eval "\$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
[[ -f ~/.scripts/fzf-git.sh ]] && source ~/.scripts/fzf-git.sh

if [[ -x \$(command -v perl) && \$(perl -Mlocal::lib -e '1' 2>/dev/null) ]]; then
    eval "\$(perl -I$HOME/perl5/lib/perl5 -Mlocal::lib=\$HOME/perl5)"
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
brew upgrade --quiet 2> /dev/null
source ~/.profile

echo --------------------------PATH SET-------------------------------
echo $PATH
echo -----------------------------------------------------------------

# Check if Ruby is properly linked via Homebrew
ruby_path=$(which ruby)
if [[ "$ruby_path" != *"linuxbrew"* ]]; then
    echo "ruby is not linked via Homebrew. Linking ruby..."
    brew link --overwrite ruby
    if [ $? -eq 0 ]; then
        echo "ruby has been successfully linked via Homebrew."
    else
        echo "Failed to link ruby via Homebrew."
        exit 1
    fi
else
    echo "ruby is linked via Homebrew."
fi

# Create a brew list of installed packages into an array
BREW_LIST_ARRAY=($(brew list -1))

# Read JSON and process packages
jq -r '.packages | to_entries[] | .key' <<< "$CONFIG_JSON" | while IFS= read -r package; do
    install_status=$(jq -r ".packages[\"$package\"].install" <<< "$CONFIG_JSON")
    base_package=$(basename "$package")

    if [[ " ${BREW_LIST_ARRAY[*]} " =~ " ${base_package} " ]]; then
        action="already installed"
        [[ "$install_status" == "false" ]] && action="set to uninstall" && brew uninstall --quiet "$package"
        [[ "$install_status" == "skip" ]] && action="set to skip"
    else
        action="not installed"
        [[ "$install_status" == "true" ]] && action="installing" && brew install --quiet "$package"
        [[ "$install_status" == "false" || "$install_status" == "skip" ]] && action="set to $install_status"
    fi

    [[ "$install_status" != "true" && "$install_status" != "false" && "$install_status" != "skip" ]] && action="invalid install status"

    echo "$package is $action."
done

# Function to create symlink with or without sudo
create_symlink() {
    src=$1
    dest=$2
    ln -sf "$src" "$dest" || sudo ln -sf "$src" "$dest"
}
# Attempt to create the symlinks
echo "Creating symlinks"
create_symlink /home/linuxbrew/.linuxbrew/bin/python3 /home/linuxbrew/.linuxbrew/bin/python
create_symlink /home/linuxbrew/.linuxbrew/bin/pip3 /home/linuxbrew/.linuxbrew/bin/pip
create_symlink /home/linuxbrew/.linuxbrew/bin/gcc /home/linuxbrew/.linuxbrew/bin/cc
echo "Finished creating symlinks"


# Enable perl in homebrew
if [[ $(echo "$CONFIG_JSON" | jq -r '.packages.perl.install') == true ]]; then
        echo "Fixing perl symlink..."
        sudo ln -sf /home/linuxbrew/.linuxbrew/bin/perl /usr/bin/perl
    #if ! perl -Mlocal::lib -e '1' &> /dev/null; then
	echo "Enabling perl cpan with defaults and permission fix"
        sudo -E PERL_MM_USE_DEFAULT=1 PERL_MM_OPT=INSTALL_BASE=$HOME/perl5 cpan local::lib
        cpan local::lib
        sudo chown -R $(whoami):root $HOME/perl5 $HOME/.cpan
        sudo chmod 775  $HOME/perl5 $HOME/.cpan -R 
    #fi
fi

# oh-my-zsh will always be installed with the latest version
[[ -e ~/.oh-my-zsh ]] && rm -rf ~/.oh-my-zsh
if [[ -x $(command -v zsh) ]]; then
	sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
	chmod -R 755 ~/.oh-my-zsh
fi

# Check if additional Neovim packages should be installed
echo "-----------------------------------------------------------------"
if [[ $(echo "$CONFIG_JSON" | jq -r '.packages.neovim.install') == true ]]; then
    echo "Calling $SCRIPT_DIR/nvim_config.sh for additional setup packages"
    # Create a temporary file to store JSON data
    temp_file=$(mktemp)
    echo "$CONFIG_JSON" > "$temp_file"
    bash "$SCRIPT_DIR/nvim_config.sh" "$temp_file"
    CONFIG_JSON=$(<"$temp_file")
    rm "$temp_file"
else
    echo "SKIPPING: Neovim components as config.json install flag is set to false."
fi

# Check if any zsh packages should be configured
echo "-----------------------------------------------------------------"
echo "Calling $SCRIPT_DIR/zsh_config.sh for additional zsh configuration"
bash "$SCRIPT_DIR/zsh_config.sh" "$CONFIG_JSON"

# Read JSON and install/uninstall plugins
echo "$CONFIG_JSON" | jq -r '.plugins | to_entries[] | "\(.key) \(.value.install) \(.value.directory) \(.value.url)"' | while read -r plugin install directory url; do
    eval directory="$directory"

    if [[ "$install" == "true" && ! -d "$directory" ]]; then
        echo "$plugin is not installed, cloning..."
        git clone "$url" "$directory"
    elif [[ "$install" == "true" && -d "$directory" ]]; then
        echo "$plugin is already installed."
    elif [[ "$install" == "false" ]]; then
        if [[ -d "$directory" ]]; then
            echo "$plugin install flag is set to false in config.json. Removing plugin directory..."
            rm -rf "$directory"
        fi
    elif [[ "$install" == "skip" ]]; then
        echo "$plugin install flag is set to skip in config.json. No action will be taken."
    elif [[ "$install" == "handled" ]]; then
        echo "$plugin has already been handled by nvim_config.sh."
    else
        echo "Invalid install status for $plugin in config.json. No action will be taken."
    fi
done

# PROFILE DEFAULTS: zsh and p10k are copied to home and can be reconfigured later.
[[ ! -e ~/.p10k.zsh ]] && cp "$SCRIPT_DIR/.p10k.zsh" ~/
cp "$SCRIPT_DIR/.zshrc" ~/

# Set default plugins
default_plugins="git web-search"

# Use jq to get the list of plugins to add
add_plugins=$(echo "$CONFIG_JSON" | jq -r '
  .plugins | to_entries[] | 
  select(.value.install == true and (.value.directory | contains("custom/plugins"))) | 
  .key')

# Combine default plugins with those from the JSON config
plugins="$default_plugins"
for plugin in $add_plugins; do
  plugins="$plugins $plugin"
done

# Convert space-separated plugins list to a format suitable for .zshrc
plugins_array="plugins=($plugins)"

# Update ~/.zshrc with the selected plugins
func_sed "s|^plugins=.*$|$plugins_array|" ~/.zshrc

# Ensure the theme is set to powerlevel10k
func_sed 's|^ZSH_THEME=.*$|ZSH_THEME="powerlevel10k/powerlevel10k"|' ~/.zshrc

# Iterate over the aliases in JSON and add them to ~/.zshrc if install is not set to false.
echo -e "\n# ----config.json----" >> ~/.zshrc
echo "$CONFIG_JSON" | jq -r '
  .packages, .plugins 
  | to_entries[] 
  | select(.value.aliases != "" and .value.install != false) 
  | .value.aliases 
  | to_entries[] 
  | "alias \(.key)=\(.value|@sh)"
' | while read -r alias_command; do
    if ! grep -qF "$alias_command" ~/.zshrc; then
        echo "Adding alias command: $alias_command"
        echo "$alias_command" >> ~/.zshrc
    else
        echo "Alias already exists: $alias_command"
    fi
done

# Iterate over the eval in JSON and add them to ~/.zshrc if install is not set to false.
echo "$CONFIG_JSON" | jq -r '
  .packages, .plugins
  | to_entries[]
  | select(.value.eval != "" and .value.install != false)
  | if (.value.eval | type) == "object" then
      .value.eval | to_entries[] | "eval \"$(\(.value))\""
    else
      "eval \"$(\(.value.eval))\""
    end
' | while read -r eval_command; do
    if ! grep -qF "$eval_command" ~/.zshrc; then
        echo "Adding eval command: $eval_command"
        echo "$eval_command" >> ~/.zshrc
    else
        echo "Eval command already exists: $eval_command"
    fi
done

# Finalise with zsh execution in Synology ash ~/.profile
command_to_add='[[ -x /home/linuxbrew/.linuxbrew/bin/zsh ]] && exec /home/linuxbrew/.linuxbrew/bin/zsh'
if ! grep -xF "$command_to_add" ~/.profile; then
    echo "$command_to_add" >> ~/.profile
fi

# Finish script with cleanup and transport
sudo rm -rf $SUDOERS_FILE
echo "Script completed successfully. You will now be transported to ZSH!!!"
exec zsh --login
