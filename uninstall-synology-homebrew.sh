#!/bin/bash

source ./functions.sh
func_initialize_env_vars

NVIM_CONFIG_URL="https://github.com/MrCee/nvim-mrcee"
NVIM_DEFAULT_CONFIG_DIR="$HOME/.config/nvim"
NVIM_APP_CONFIG_DIR="$HOME/.config/nvim-mrcee"
NVIM_APPNAME="nvim-mrcee"
NVIM_TINY_LEFTOVER_MAX_KIB=16
NVIM_TINY_LEFTOVER_MAX_FILES=3

# Set Trap for EXIT to Handle Normal Cleanup
trap 'code=$?; func_cleanup_exit $code' EXIT

# Set Trap for Interruption Signals to Handle Cleanup
trap 'func_cleanup_exit 130' INT TERM HUP QUIT ABRT ALRM PIPE

remove_nvim_state() {
    /bin/rm -rf "$HOME/.cache/$NVIM_APPNAME"
    /bin/rm -rf "$HOME/.local/share/$NVIM_APPNAME"
    /bin/rm -rf "$HOME/.local/state/$NVIM_APPNAME"
}

is_tiny_nongit_nvim_leftover() {
    local nvim_config_dir="$1"
    local du_line=""
    local size_kib=""
    local file_count=""

    [[ -d "$nvim_config_dir" ]] || return 1
    [[ ! -d "$nvim_config_dir/.git" ]] || return 1

    du_line=$(/usr/bin/du -sk "$nvim_config_dir" 2>/dev/null || true)
    size_kib=${du_line%%[[:space:]]*}

    [[ "$size_kib" =~ ^[0-9]+$ ]] || return 1

    file_count=$(/usr/bin/find "$nvim_config_dir" -type f 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d '[:space:]')
    [[ "$file_count" =~ ^[0-9]+$ ]] || return 1

    (( size_kib <= NVIM_TINY_LEFTOVER_MAX_KIB && file_count <= NVIM_TINY_LEFTOVER_MAX_FILES ))
}

remove_nvim_config_if_canonical_or_tiny_leftover() {
    local nvim_config_dir="$1"
    local existing_origin=""

    if [[ ! -d "$nvim_config_dir" ]]; then
        return 0
    fi

    if [[ ! -d "$nvim_config_dir/.git" ]]; then
        if is_tiny_nongit_nvim_leftover "$nvim_config_dir"; then
            echo "Removing tiny non-git Neovim leftover: $nvim_config_dir"
            /bin/rm -rf "$nvim_config_dir"
            remove_nvim_state
        else
            echo "Skipping $nvim_config_dir because it is not a git checkout and is not a tiny leftover."
        fi
        return 0
    fi

    existing_origin=$(/usr/bin/git -C "$nvim_config_dir" remote get-url origin 2>/dev/null || true)
    if [[ "$existing_origin" == "$NVIM_CONFIG_URL" ]]; then
        /bin/rm -rf "$nvim_config_dir"
        remove_nvim_state
    else
        echo "Skipping $nvim_config_dir because its origin is '$existing_origin', not '$NVIM_CONFIG_URL'."
    fi
}

# Setup sudoers file
func_sudoers

# Ensure sudo credentials are cached
sudo -v || { echo "Failed to cache sudo credentials"; exit 1; }

read -rp "This will uninstall homebrew and remove all its folders. Do you want to continue? (yes/no): " response

[[ $DARWIN == 0 ]] && sudo chmod 775 /home /home/linuxbrew

# Convert the response to lowercase and trim leading/trailing whitespace
response=$(echo "$response" | tr '[:upper:]' '[:lower:]' | xargs)
# Check the response
if [[ $response == "yes" || $response == "y" ]]; then
	echo "Uninstalling Homebrew..."
elif [[ $response == "no" || $response == "n" ]]; then
	exit 0
else
    echo "Invalid response. Please enter 'yes' or 'no'."
	exit 1
fi

DEL_NVIM=0
read -rp "Do you also want to remove the canonical Neovim config and cached files? (yes/no): " response
# Convert the response to lowercase and trim leading/trailing whitespace
response=$(echo "$response" | tr '[:upper:]' '[:lower:]' | xargs)

# Check the response
if [[ $response == "yes" || $response == "y" ]]; then
	DEL_NVIM=1
elif [[ $response == "no" || $response == "n" ]]; then
	DEL_NVIM=0
	echo "Skipping removal of Neovim config"
else
    echo "Invalid response. Please enter 'yes' or 'no'."
	exit 1
fi

if [[ $DEL_NVIM == 1 ]]; then
    for nvim_config_dir in "$NVIM_DEFAULT_CONFIG_DIR" "$NVIM_APP_CONFIG_DIR"; do
        remove_nvim_config_if_canonical_or_tiny_leftover "$nvim_config_dir"
    done
fi

NONINTERACTIVE=1 sudo /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"

# Restore default profile

if [[ $DARWIN == 0 ]] ; then
    sudo cp /etc.defaults/profile "$HOME/.profile"
    sudo rm -rf /usr/bin/ldd /etc/ld.so.conf /etc/os-release
    [ -L /usr/bin/perl ] && [[ $(readlink /usr/bin/perl) =~ .linuxbrew ]] && sudo rm -rf /usr/bin/perl
    [ -L /bin/zsh ] && [[ $(readlink /bin/zsh) =~ .linuxbrew ]] && sudo rm -rf /bin/zsh
    sudo rm -rf /home/linuxbrew
	sudo umount -l /home
	sudo rmdir /home # !!! THE rmdir COMMAND ONLY REMOVES IF EMPTY SO USE IT !!!
fi

[[ $DARWIN == 1 ]] && sudo rm ~/.zprofile > /dev/null 2>&1

rm -rf ~/.cache/Homebrew
rm -rf ~/.cache/p10k*
rm -rf ~/.oh-my-zsh
rm -rf ~/.p10k.zsh
rm -rf ~/.zshrc
sudo rm -rf ~/perl5 ~/.cpan ~/.npm

func_cleanup_exit

echo "Uninstall complete. Returning to the default shell.."


if [[ $DARWIN == 0 ]] ; then
	source "$HOME/.profile"
    exec /bin/ash --login
fi
if [[ $DARWIN == 1 ]] ; then
	sudo rm  ~/.zshrc ~/.zprofile > /dev/null 2>&1
	source /etc/profile
	/bin/zsh --login
fi
