#!/bin/bash

# Check if the script is being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "🚫 This file should not be run directly; it should be sourced from the main script."
    exit 1
fi

# -----------------------------------------------
# Function: func_sed
# Description: Performs a sed operation in a portable way.
# Arguments:
#   $1 - Sed expression
#   $2 - Input file
# -----------------------------------------------
func_sed() {
    local sed_expr="$1"
    local input_file="$2"
    local tmp_file

    tmp_file=$(mktemp) || { echo "❌ Error: Failed to create temporary file." >&2; return 1; }

    # Run sed and capture output
    if sed -E "$sed_expr" "$input_file" > "$tmp_file"; then
        # Check if the file actually needs changes
        if cmp -s "$input_file" "$tmp_file"; then
            echo "✅ Sed operation: No changes needed in '$input_file'."
        else
            mv "$tmp_file" "$input_file" || {
                echo "❌ Error: Failed to move temporary file to '$input_file'." >&2
                rm -f "$tmp_file"
                return 1
            }
            echo "🛠️ Sed operation: Fix applied in '$input_file' :: '$sed_expr'"
        fi
    else
        # Handle sed errors
        echo "❌ Error: Sed operation failed for '$input_file' with expression '$sed_expr'" >&2
        rm -f "$tmp_file"
        return 1
    fi
    # Cleanup temporary file
    rm -f "$tmp_file"

    return 0  # Ensure the function returns success
}


# -----------------------------------------------
# Function: func_sudoers
# Description: Sets up the sudoers file with necessary permissions.
# Handles both macOS and Synology NAS environments.
# -----------------------------------------------
func_sudoers() {
    # Determine the sudoers directory and file path based on OS
    local sudoers_dir=""
    local current_user=""
    local is_synology=0

    if [[ $DARWIN -eq 0 ]]; then
        sudoers_dir="/etc/sudoers.d"
    elif [[ $DARWIN -eq 1 ]]; then
        sudoers_dir="/private/etc/sudoers.d"
    else
        # Detect Synology DSM
        if [[ -f /usr/syno/bin/synopkg ]]; then
            sudoers_dir="/etc/sudoers.d"
            is_synology=1
        else
            echo "❌ Unsupported OS."
            return 1
        fi
    fi

    sudoers_file="$sudoers_dir/custom_homebrew_sudoers"
    current_user=$(whoami)

    # Register the sudoers file for cleanup early
    export SUDOERS_FILE="$sudoers_file"

    # Check if sudoers setup is already done and the file exists
    if [[ "${SUDOERS_SETUP_DONE:-0}" -eq 1 && -f "$sudoers_file" ]]; then
        echo "✅ Sudoers setup already completed and sudoers file exists. Skipping."
        return 0
    fi

    # Proceed with sudoers setup
    echo "🛠️ Setting up sudoers file..."

    # Cache sudo credentials upfront
    sudo -k  # Reset cached credentials
    if ! sudo -v; then
        echo "❌ Failed to cache sudo credentials." >&2
        return 1
    fi

    # Ensure the sudoers directory exists
    if [[ ! -e "$sudoers_dir" ]]; then
        echo "🔧 Creating sudoers directory at '$sudoers_dir'..."
        sudo mkdir -p "$sudoers_dir" || { echo "❌ Failed to create '$sudoers_dir'."; return 1; }
    fi

    # Set the correct permissions for the sudoers directory
    sudo chmod 0755 "$sudoers_dir" || { echo "❌ Failed to set permissions for '$sudoers_dir'."; return 1; }

    # Install the sudoers file using tee
    echo "📝 Installing sudoers file at '$sudoers_file'..."
    sudo tee "$sudoers_file" > /dev/null <<EOF
Defaults syslog=authpriv
root ALL=(ALL) ALL
$current_user ALL=NOPASSWD: ALL
EOF

    # Set permissions for the sudoers file
    sudo chmod 0440 "$sudoers_file" || { echo "❌ Failed to set permissions for '$sudoers_file'."; return 1; }

    # Validate the sudoers file syntax only if visudo is available
    if command -v visudo > /dev/null 2>&1; then
        if ! sudo visudo -cf "$sudoers_file"; then
            echo "❌ Sudoers file syntax is invalid. Removing the faulty file." >&2
            sudo rm -f "$sudoers_file"
            return 1
        fi
        echo "✅ Sudoers file validated successfully."
    else
        if [[ $is_synology -eq 1 ]]; then
            echo "⚠️ Warning: 'visudo' not available on Synology NAS. Please ensure the sudoers file syntax is correct." >&2
        else
            echo "⚠️ Warning: 'visudo' not found. Skipping sudoers file validation." >&2
        fi
    fi

    echo "✅ Sudoers file installed successfully at '$sudoers_file'."

    # Mark sudoers setup as done
    export SUDOERS_SETUP_DONE=1
}

# -----------------------------------------------
# Function: func_cleanup_exit
# Description: Cleans up the sudoers file upon script exit or interruption.
# Arguments:
#   $1 - Exit code (default: 0)
# -----------------------------------------------
func_cleanup_exit() {
    local exit_code=${1:-0}  # Use $1 if provided, otherwise default to 0

    [[ $DEBUG == 1 ]] && echo "🔄 Debug: func_cleanup_exit called with exit code $exit_code."

    # Restore original stty settings
    if [[ -n "${orig_stty:-}" ]]; then
        stty "$orig_stty"
    fi

    if [[ $exit_code -eq 0 ]]; then
        echo "🎉 Script completed successfully."
    else
        echo "⚠️ Script exited with code $exit_code."
    fi

    # Perform cleanup if the sudoers file exists or if the flag is set
    if [[ -n "${SUDOERS_FILE:-}" ]]; then
        if [[ -f "$SUDOERS_FILE" ]]; then
            echo "🗑️ Removing sudoers file at '$SUDOERS_FILE'..."
            sudo rm -f "$SUDOERS_FILE" 2>/dev/null && echo "🗑️ Sudoers file removed."
        else
            echo "ℹ️ Sudoers file '$SUDOERS_FILE' does not exist. No removal needed."
        fi

        echo "🔒 Revoking sudo access..."
        sudo -k && echo "🔒 Sudo access revoked."

        # Reset the SUDOERS_SETUP_DONE flag
        export SUDOERS_SETUP_DONE=0
    else
        echo "🔍 Debug: SUDOERS_FILE is not set."
    fi

    # Unset the EXIT trap to prevent recursion
    trap - EXIT

    # Exit with the original exit code if it is non-zero
    if [[ $exit_code -ne 0 ]]; then
        exit "$exit_code"
    fi
}

# -----------------------------------------------
# Function: func_check_sudoers
# Description: Checks if the sudoers file exists without modifying it.
# -----------------------------------------------
func_check_sudoers() {
    if [[ $DARWIN -eq 0 ]]; then
        sudoers_dir="/etc/sudoers.d"
    elif [[ $DARWIN -eq 1 ]]; then
        sudoers_dir="/private/etc/sudoers.d"
    else
        # Detect Synology DSM
        if [[ -f /usr/syno/bin/synoservice ]]; then
            sudoers_dir="/etc/sudoers.d"
        else
            echo "❌ Unsupported OS." >&2
            return 1
        fi
    fi

    sudoers_file="$sudoers_dir/custom_homebrew_sudoers"

    if [[ -f "$sudoers_file" ]]; then
        echo "✅ Sudoers file exists at '$sudoers_file'."
    else
        echo "❌ Sudoers file does not exist at '$sudoers_file'."
    fi
}

# -----------------------------------------------
# Function: func_initialize_env_vars
# Description: Initializes environment variables based on the operating system.
# -----------------------------------------------
func_initialize_env_vars() {
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
		DARWIN=0
        # Expected path for Linuxbrew
        HOMEBREW_PATH="/home/linuxbrew/.linuxbrew"
        DEFAULT_GROUP="root"
	else
        printf "❌ Unsupported OS: %s\n" "$os" >&2
        return 1
    fi

    # Export DARWIN and HOMEBREW_PATH after setting their values
    export DARWIN HOMEBREW_PATH
}

