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
