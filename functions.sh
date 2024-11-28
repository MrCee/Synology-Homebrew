#!/bin/bash

# Ensure the script is sourced, not executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "🚫 This file should not be run directly; it should be sourced from the main script."
    exit 1
fi

# Function to initialize environment variables
func_initialize_env_vars() {
    # Determine if the OS is Darwin (macOS) or not (Synology)
    if [[ "$(uname)" == "Darwin" ]]; then
        DARWIN=1
    else
        DARWIN=0
    fi

    # Set Homebrew path based on installation
    if [[ $DARWIN -eq 1 ]]; then
        HOMEBREW_PATH="/usr/local/bin"
    else
        HOMEBREW_PATH="/usr/local/bin"  # Adjust if different for Synology
    fi

    # Set default group (adjust as necessary)
    DEFAULT_GROUP="staff"
}

# Function to set up sudoers file
func_sudoers() {
    # Example: Grant the current user passwordless sudo for specific commands
    # Modify as per your security policies
    SUDOERS_FILE="/etc/sudoers.d/$(whoami)"
    if [[ ! -f "$SUDOERS_FILE" ]]; then
        echo "$(whoami) ALL=(ALL) NOPASSWD:ALL" | sudo tee "$SUDOERS_FILE" > /dev/null
        sudo chmod 440 "$SUDOERS_FILE"
        SUDOERS_SETUP_DONE=1
    else
        SUDOERS_SETUP_DONE=1
    fi
}

# Function to perform cleanup on exit
func_cleanup_exit() {
    local exit_code="$1"
    stty "$orig_stty"
    # Additional cleanup tasks if necessary
    exit "$exit_code"
}

# Function to install Homebrew if it's not installed
install_homebrew() {
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

# Function to initialize Homebrew
initialize_homebrew() {
    eval "$("$HOMEBREW_PATH"/brew shellenv)"
}

# Function to define package lists based on DARWIN
define_package_lists() {
    packages=()
    if [[ $DARWIN -eq 0 ]]; then
        # Synology-specific packages
        packages=("git" "yq" "ruby")
    elif [[ $DARWIN -eq 1 ]]; then
        # macOS-specific packages
        packages=("git" "yq" "ruby" "python3")
    fi
}

# Function to install a package if it's missing
install_if_missing() {
    local package="$1"
    if ! "$HOMEBREW_PATH"/brew list --formula -1 | grep -Fxq "$package"; then
        echo "🛠️ Installing $package..."
        if "$HOMEBREW_PATH"/brew install --quiet "$package"; then
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

# Function to uninstall a package
uninstall_package() {
    local package="$1"
    if "$HOMEBREW_PATH"/brew list --formula -1 | grep -Fxq "$package"; then
        echo "🚫 Uninstalling $package..."
        if "$HOMEBREW_PATH"/brew uninstall --quiet "$package"; then
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

# Function to upgrade all installed Homebrew packages
upgrade_packages() {
    echo "🔄 Upgrading all Homebrew packages..."
    "$HOMEBREW_PATH"/brew upgrade --quiet
    if [[ $? -eq 0 ]]; then
        echo "✅ Upgrade completed."
    else
        echo "❌ Upgrade encountered issues." >&2
        failed_packages+=("brew upgrade")
    fi
}

# Function to perform in-place sed operations
func_sed() {
    local sed_expression="$1"
    local file="$2"
    # Use temporary file for compatibility with Bash 3.x
    sed "$sed_expression" "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
}
