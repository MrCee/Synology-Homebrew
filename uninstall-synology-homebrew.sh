#!/bin/bash

source ./functions.sh
func_initialize_env_vars

# Set Trap for EXIT to Handle Normal Cleanup
trap 'code=$?; func_cleanup_exit $code' EXIT

# Set Trap for Interruption Signals to Handle Cleanup
trap 'func_cleanup_exit 130' INT TERM HUP QUIT ABRT ALRM PIPE

# Setup sudoers file
func_sudoers

# Ensure sudo credentials are cached
sudo -v || { echo "Failed to cache sudo credentials"; exit 1; }

read -rp "This will uninstall homebrew and remove all its folders. Do you want to continue? (yes/no): " response

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
read -rp "Do you also want to remove kickstart.nvim config and cached files? (yes/no): " response
# Convert the response to lowercase and trim leading/trailing whitespace
response=$(echo "$response" | tr '[:upper:]' '[:lower:]' | xargs)

# Check the response
if [[ $response == "yes" || $response == "y" ]]; then
	DEL_NVIM=1
elif [[ $response == "no" || $response == "n" ]]; then
	DEL_NVIM=0
	echo "Skipping removal of nvim"
else
    echo "Invalid response. Please enter 'yes' or 'no'."
	exit 1
fi

if [[ $DEL_NVIM == 1 ]]; then
rm -rf ~/.config/nvim-kickstart
rm -rf ~/.cache/nvim-kickstart
rm -rf ~/.local/share/nvim-kickstart
rm -rf ~/.local/state/nvim-kickstart
fi

NONINTERACTIVE=1 sudo /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"

# Restore default profile

if [[ $DARWIN == 0 ]] ; then
    sudo cp /etc.defaults/profile "$HOME/.profile"
    sudo rm -rf /usr/bin/ldd /etc/ld.so.conf /etc/os-release
    [ -L /usr/bin/perl ] && [[ $(readlink /usr/bin/perl) =~ .linuxbrew ]] && sudo rm -rf /usr/bin/perl
    [ -L /bin/zsh ] && [[ $(readlink /bin/zsh) =~ .linuxbrew ]] && sudo rm -rf /bin/zsh
    sudo rm -rf /home/linuxbrew

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
