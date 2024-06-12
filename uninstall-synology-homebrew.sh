#!/bin/bash

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


# Prompt user
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

if [[ -f /home/linuxbrew/.linuxbrew/bin/brew ]]; then
NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"
fi
# Restore default profile
sudo cp /etc.defaults/profile "$HOME/.profile"
rm -rf ~/.cache/Homebrew
rm -rf ~/.cache/p10k*
rm -rf ~/.oh-my-zsh
rm -rf ~/.p10k.zsh
rm -rf ~/.zshrc

# Remove installed files and directories
sudo rm -rf /usr/bin/ldd /etc/ld.so.conf /etc/os-release
sudo rm -rf ~/perl5 ~/.cpan ~/.npm

# Remove Symbolic links
[ -L /usr/bin/perl ] && [[ $(readlink /usr/bin/perl) =~ .linuxbrew ]] && sudo rm -rf /usr/bin/perl

# echo attempting to delete linuxbrew directory....
sudo rm -rf /home/linuxbrew

echo "Uninstall complete. You wil need to run 'source ~/.profile' for your current shell"

# Switch to ash and source the profile
/bin/ash -c 'source "$HOME/.profile"; exec /bin/ash'


