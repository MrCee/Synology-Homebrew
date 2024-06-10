#!/bin/bash
clear

# Get the directory containing this script
case "$0" in
    /*) script_path="$0" ;;
    *) script_path="$(pwd)/$0" ;;
esac

# Resolve the directory path
script_dir="$(cd "$(dirname "$script_path")" && pwd)"

# Change to the script directory
cd "$script_dir" || { echo "Failed to change directory to $script_dir"; exit 1; }
echo "Working directory: $script_dir"

# Define the location of JSON
CONFIG_JSON_PATH="$script_dir/config.json"

# Ensure config.json exists
if [[ ! -f "$CONFIG_JSON_PATH" ]]; then
    echo "config.json not found in $script_dir"
    exit 1
fi

# Format JSON to ensure compatibility
sed -E -i 's/([^\\])\\([^\\"])/\1\\\\\2/g' "$CONFIG_JSON_PATH"
sed -E -i 's/(^.*:\s*\"[^\\]*?)(\".*?)(\".*?\"$)/\1\\\2\\\3/g' "$CONFIG_JSON_PATH"
sed -E -i '/"install": "skip"/ s/\"skip\"/\"skip\"/;t;s/(skip)/"\1"/' "$CONFIG_JSON_PATH"


# Update plugin keys and write to a temporary file
temp_file=$(mktemp)

# Update plugin keys and write to the temporary file
if ! jq '{
  packages: .packages,
  plugins: (.plugins | to_entries | map({key: (.value.url | split("/")[-1]), value: .value}) | from_entries)
}' "$CONFIG_JSON_PATH" > "$temp_file"; then
    echo "Failed to process JSON with jq."
    exit 1
fi

# Replace the original config.json with the updated version
mv "$temp_file" "$CONFIG_JSON_PATH"
echo "config.json has been updated successfully."

# Validate JSON
if ! jq empty "$CONFIG_JSON_PATH" > /dev/null 2>&1; then
    echo "Invalid JSON."
    exit 1
fi
echo "JSON is valid."

# Read the content of JSON into the CONFIG_JSON variable
CONFIG_JSON=$(<"$CONFIG_JSON_PATH")

# Function to display the menu
display_menu() {
    cat <<EOF
Select your install type:

1) Synology-Homebrew: Minimal install will provide the homebrew basics, ignore packages in config.json, leaving the rest to you.
   ** If you are running this script after a full setup, you can use this option to uninstall packages previously installed by option 2

2) Synology-Homebrew: Full setup includes packages in config.json
   ** This is recommended if you want to get started with Neovim

Enter selection:
EOF
}

# Function to display information based on the selection
display_info() {
    case "$1" in
        1)
            cat <<EOF
Minimal install selected
Minimal install will provide the homebrew basics and ignore config.json
** If you are running this script after a full setup, you can use this option to uninstall packages in config.json
** Plugins and themes should be removed manually
EOF
            ;;
        2)
            cat <<EOF
Full setup selected
Full setup includes packages in config.json
EOF
            ;;
        *)
            echo "Invalid selection."
            ;;
    esac
}

while true; do
    clear
    display_menu
    read -r selection

    case "$selection" in
        1|2)
            break
            ;;
        *)
            echo "Invalid selection. Please enter 1 or 2."
            read -r -p "Press Enter to continue..."
            ;;
    esac
done

clear
display_info "$selection"

if [[ "$selection" -eq 2 && ! -f "$CONFIG_JSON_PATH" ]]; then
    echo "config.json not found in this directory"
    exit 1
fi

case "$selection" in
    1)
        echo "Starting Minimal Install..."
        # Update install fields to false
        CONFIG_JSON=$(jq '.packages |= with_entries(.value |= if .install == true then .install = false else . end)' <<< "$CONFIG_JSON")
        ;;
    2)
        echo "Starting Full Setup..."
        # No need to re-read config.json, already read at the beginning
        ;;
esac

export HOMEBREW_NO_ENV_HINTS=1
export HOMEBREW_NO_AUTO_UPDATE=1

# Check if the script is being run as root
if [ "$EUID" -eq 0 ]; then
    echo "This script should not be run as root. Please run it as a regular user, although we will need root password in a second..."
    exit 1
fi

# Prompt for root password and cache credentials
sudo -v

# Check if sudo credentials are cached
if [ $? -eq 1 ]; then
    echo "Incorrect password or user is not allowed to use sudo."
    exit 1
fi

# Keep sudo credentials updated
while true; do
    sudo -v
    sleep 50
done &
KEEP_SUDO_PID=$!

# Ensure the background sudo refresh process is terminated when the script exits
cleanup() {
    kill $KEEP_SUDO_PID
}
trap cleanup EXIT

# Check all prerquisites of this script
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
    exit 1
fi

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

# Create a new .profile and add custom paths
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
BREW_LIST_ARRAY=()
while IFS= read -r line; do
    BREW_LIST_ARRAY+=("$line")
done <<< $(brew list -1)


# Read JSON and process packages
echo "$CONFIG_JSON" | jq -r '.packages | to_entries[] | .key' | while read -r package; do
    install_status=$(echo "$CONFIG_JSON" | jq -r ".packages[\"$package\"].install")
    if [[ "${BREW_LIST_ARRAY[*]}" =~ "$package" ]]; then
        if [[ "$install_status" == "true" ]]; then
            echo "$package is already installed."
        elif [[ "$install_status" == "false" ]]; then
            echo "$package is set to uninstall in config.json and will now be uninstalled"
            brew uninstall --quiet "$package"
        elif [[ "$install_status" == "skip" ]]; then
            echo "$package is set to skip in config.json. No action will be taken."
        else
            echo "Invalid install status for $package in config.json. No action will be taken."
        fi
    else
        if [[ "$install_status" == "true" ]]; then
            echo "$package is not installed, installing..."
            brew install --quiet "$package"
        elif [[ "$install_status" == "false" ]]; then
            echo "$package is not installed and is set to uninstall in config.json. No action will be taken."
        elif [[ "$install_status" == "skip" ]]; then
            echo "$package is not installed and is set to skip in config.json. No action will be taken."
        else
            echo "Invalid install status for $package in config.json. No action will be taken."
        fi
    fi
done

echo "Creating symlinks"
sudo ln -sf /home/linuxbrew/.linuxbrew/bin/python3 /home/linuxbrew/.linuxbrew/bin/python
sudo ln -sf /home/linuxbrew/.linuxbrew/bin/pip3 /home/linuxbrew/.linuxbrew/bin/pip
sudo ln -sf /home/linuxbrew/.linuxbrew/bin/gcc /home/linuxbrew/.linuxbrew/bin/cc

# Enable perl in homebrew
if [[ $(echo "$CONFIG_JSON" | jq -r '.packages.perl.install') == true ]]; then
    [[ ! -e /usr/bin/perl ]] && sudo ln -sf /home/linuxbrew/.linuxbrew/bin/perl /usr/bin/perl
    if ! perl -Mlocal::lib -e '1' &> /dev/null; then
	echo "Enabling perl cpan with defaults and permission fix"
        sudo -E PERL_MM_USE_DEFAULT=1  PERL_MM_OPT=INSTALL_BASE=$HOME/perl5 cpan local::lib
        sudo chown -R $(whoami):root ~/perl5 $HOME/.cpan
    fi
fi

# oh-my-zsh will always be installed with the latest version
[[ -e ~/.oh-my-zsh ]] && rm -rf ~/.oh-my-zsh
if [[ -x $(command -v zsh) ]]; then
	sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
	chmod -R 755 ~/.oh-my-zsh
fi

# Check if additional Neovim packages should be installed
echo "-----------------------------------------------------------------"
if [[ $(echo "$CONFIG_JSON" | jq -r '.packages.neovim.install') == "true" ]]; then
    echo "Calling $script_dir/nvim_config.sh for additional setup packages"
    # Create a temporary file to store JSON data
    temp_file=$(mktemp)
    echo "$CONFIG_JSON" > "$temp_file"
    bash "$script_dir/nvim_config.sh" "$temp_file"
    CONFIG_JSON=$(<"$temp_file")
    rm "$temp_file"
else
    echo "SKIPPING: Neovim components as config.json install flag is set to false."
fi

# Check if any zsh packages should be configured
echo "Calling $script_dir/zsh_config.sh for additional zsh configuration"
# Create a temporary file to store JSON data
temp_file=$(mktemp)
echo "$CONFIG_JSON" > "$temp_file"
bash "$script_dir/zsh_config.sh" "$temp_file"
rm "$temp_file"

# Read JSON and install plugins
echo "$CONFIG_JSON" | jq -r '.plugins | to_entries[] | "\(.key) \(.value.install) \(.value.directory) \(.value.url)"' | while read -r plugin install directory url; do
    eval directory="$directory"

    if [[ "$install" == "true" && ! -d "$directory" ]]; then
        echo "$plugin is not installed, cloning..."
        git clone "$url" "$directory"
    elif [[ "$install" == "true" && -d "$directory" ]]; then
        echo "$plugin is already installed."
    elif [[ "$install" == "false" ]]; then
        echo "$plugin install flag is set to false in config.json and will be skipped."
    elif [[ "$install" == "skip" ]]; then
        echo "$plugin install flag is set to skip in config.json. No action will be taken."
    elif [[ "$install" == "handled" ]]; then
        echo "$plugin has already been handled by nvim_config.sh."
    else
        echo "Invalid install status for $plugin in config.json. No action will be taken."
    fi
done

# PROFILE DEFAULTS: zsh and p10k are copied to home and can be reconfigured later.
[[ ! -e ~/.p10k.zsh ]] && cp "$script_dir/.p10k.zsh" ~/
cp "$script_dir/.zshrc" ~/
# Add themes and plugins to ~/.zshrc just incase we need to:
sed -E -i 's/ZSH_THEME.*$/ZSH_THEME=powerlevel10k\/powerlevel10k/' ~/.zshrc
sed -E -i 's/plugins=.*$/plugins=(git zsh-autosuggestions zsh-syntax-highlighting web-search)/' ~/.zshrc

# Iterate over the aliases in JSON and add them to ~/.zshrc
echo -e "\n# ----config.json----" >> ~/.zshrc
echo "$CONFIG_JSON" | jq -r '.packages, .plugins | to_entries[] | select(.value.aliases != "" and .value.install != false) | .value.aliases | to_entries[] | "alias \(.key)=\(.value|@sh)"'| while read -r alias_command; do
    if ! grep -qF "$alias_command" ~/.zshrc; then
        echo "Adding alias command: $alias_command"
        echo "$alias_command" >> ~/.zshrc
    else
        echo "Alias already exists: $alias_command"
    fi
done

# Iterate over the eval in JSON and add them to ~/.zshrc
echo "$CONFIG_JSON" | jq -r ' .packages,.plugins | to_entries[] | select(.value.eval != "" and .value.install != false) | "eval \"$(\(.value.eval))\""' | while read -r eval_command; do
    if ! grep -qF "$eval_command" ~/.zshrc; then
        echo "Adding eval command: $eval_command"
        echo "$eval_command" >> ~/.zshrc
    else
        echo "Eval command already exists: $eval_command"
    fi
done

# Remove Synology packages once brew is installed
if [[ $(brew --version) ]]; then
    [[ $(synopkg version git) ]] && sudo synopkg uninstall git > /dev/null 2>&1 && echo Uninstalled community packaged git
    [[ $(synopkg version ruby) ]] && sudo synopkg uninstall ruby > /dev/null 2>&1 && echo Uninstalled community packaged ruby
fi

# Finalise with zsh execution in Synology ash ~/.profile
command_to_add='[[ -x /home/linuxbrew/.linuxbrew/bin/zsh ]] && exec /home/linuxbrew/.linuxbrew/bin/zsh'
if ! grep -xF "$command_to_add" ~/.profile; then
    echo "$command_to_add" >> ~/.profile
fi

echo "Script completed successfully. Sourcing profile now..."
source ~/.profile



