#!/bin/bash

source ./functions.sh
func_initialize_env_vars

NVIM_CONFIG_URL="https://github.com/MrCee/nvim-mrcee"
NVIM_DEFAULT_CONFIG_DIR="$HOME/.config/nvim"
NVIM_APP_CONFIG_DIR="$HOME/.config/nvim-mrcee"
NVIM_APPNAME="nvim-mrcee"

# Set Trap for EXIT to Handle Normal Cleanup
trap 'code=$?; func_cleanup_exit $code' EXIT

# Set Trap for Interruption Signals to Handle Cleanup
trap 'func_cleanup_exit 130' INT TERM HUP QUIT ABRT ALRM PIPE

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
        if [[ ! -d "$nvim_config_dir" ]]; then
            continue
        fi

        if [[ ! -d "$nvim_config_dir/.git" ]]; then
            echo "Skipping $nvim_config_dir because it is not a git checkout of the canonical Neovim config."
            continue
        fi

        existing_origin=$(git -C "$nvim_config_dir" remote get-url origin 2>/dev/null || true)
        if [[ "$existing_origin" == "$NVIM_CONFIG_URL" ]]; then
            rm -rf "$nvim_config_dir"
            rm -rf "$HOME/.cache/$NVIM_APPNAME"
            rm -rf "$HOME/.local/share/$NVIM_APPNAME"
            rm -rf "$HOME/.local/state/$NVIM_APPNAME"
        else
            echo "Skipping $nvim_config_dir because its origin is '$existing_origin', not '$NVIM_CONFIG_URL'."
        fi
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
