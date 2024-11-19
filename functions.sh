#!/bin/bash

# Check if the script is being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This file should not be run directly, it should be sourced from main script."
    exit 1
fi

# Function to perform sed operation in a portable way
# Arguments:
#   $1 - Sed expression
#   $2 - Input file
func_sed() {
    local tmp_file=$(mktemp)
    sed_output=$(sed -E "$1" "$2" > "$tmp_file" 2>&1)
    sed_exit_code=$?

    if [ $sed_exit_code -eq 0 ]; then
        if cmp -s "$2" "$tmp_file"; then
            echo "Sed operation: No changes needed in '$2'."
        else
            mv "$tmp_file" "$2"
            echo "Sed operation: Fix applied in '$2' :: '$1'"
        fi
    else
        echo "Error: Sed operation failed - $sed_output"
        return $sed_exit_code
    fi
    
    [[ -f "$tmp_file" ]] && rm "$tmp_file"
}

func_sudoers() {
    local sudoers_file="/etc/sudoers.d/custom_homebrew_sudoers"
    local current_user=$(whoami)

    # Cleanup function on exit or interruption
    cleanup() {
        echo -e "\nAborting install..."
        sudo rm -f "$sudoers_file"
        sudo -k
        echo "Sudo access revoked."
        exit 1
    }

    # Set traps for signals to ensure cleanup on exit or termination
    trap cleanup INT TERM HUP QUIT ABRT ALRM PIPE

    # Cache sudo credentials
    sudo -k
    if ! sudo -v; then
        echo "Failed to cache sudo credentials" >&2
        exit 1
    fi

    # Install the sudoers file
    sudo install -m 0440 /dev/stdin "$sudoers_file" <<EOF
Defaults syslog=authpriv
root ALL=(ALL) ALL
$current_user ALL=NOPASSWD: ALL
EOF
}


# Initialize variables without exporting immediately
DARWIN=0
HOMEBREW_PATH=""
DEFAULT_GROUP="root"

# Function to determine the expected Homebrew installation path
func_get_os_vars() {
    local arch os
    arch=$(uname -m)
    os=$(uname -s)

    if [[ "$os" == "Darwin" ]]; then
        DARWIN=1
	DEFAULT_GROUP="staff"
	if [[ "$arch" == "arm64" ]]; then
            # Expected path for Apple Silicon (M1, M2) macOS
            HOMEBREW_PATH="/opt/homebrew"
        else
            # Expected path for Intel macOS
            HOMEBREW_PATH="/usr/local"
        fi
    elif [[ "$os" == "Linux" ]]; then
        # Expected path for Linuxbrew
        HOMEBREW_PATH="/home/linuxbrew/.linuxbrew"
	DEFAULT_GROUP="root"
    else
        printf "Unsupported OS: %s\n" "$os" >&2
        return 1
    fi

    # Export DARWIN and HOMEBREW_PATH after setting their values
    export DARWIN HOMEBREW_PATH
}

RUBY_PATH=""
GEM_BIN_PATH=""

func_get_ruby_gem() {
    # Get the path where Homebrew installed Ruby
    RUBY_PATH=$(brew --prefix ruby)

    # Locate the latest Ruby gems directory under Homebrew's Ruby path
    GEM_BIN_PATH="$(find "$RUBY_PATH/lib/ruby/gems" -type d -name '[0-9]*' | sort -V | tail -n 1)/bin"

    # Export the paths for use in the current session
    export RUBY_PATH GEM_BIN_PATH
}

