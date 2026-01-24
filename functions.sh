#!/bin/bash

# -----------------------------------------------------------------------------
# functions.sh
#
# Library file — must be sourced by install-synology-homebrew.sh
# Do NOT execute directly.
# -----------------------------------------------------------------------------

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

    echo "✅ Sudoers file installed successfully at '$sudoers_file'."

    # Mark sudoers setup as done
    export SUDOERS_SETUP_DONE=1
}



# -----------------------------------------------
# Function: func_setup_logging
# Description: Sets up logging by redirecting stdout and stderr to a log file
# Arguments:
#   $1 - Path to the log file
# -----------------------------------------------
func_setup_logging() {
    local log_file="$1"

    # Save original stdout and stderr
    exec 3>&1 4>&2

    # Redirect all output to both terminal and log file (overwrite each run)
    exec > >(tee "$log_file") 2>&1

    # Log the start time
    echo "=== Script Started at $(date) ==="
}

# -----------------------------------------------
# Function: func_cleanup_exit
# Description: Cleans up the environment upon script exit or interruption.
#              Restores stdout and stderr, closes duplicated file descriptors,
#              and performs other necessary cleanup tasks.
# Arguments:
#   $1 - Exit code (default: 0)
# -----------------------------------------------
func_cleanup_exit() {
    local exit_code=${1:-0}  # Use $1 if provided, otherwise default to 0

    [[ $DEBUG == 1 ]] && echo "🔄 Debug: func_cleanup_exit called with exit code $exit_code."

    # Restore original stdout and stderr
    exec 1>&3 2>&4

    # Close the duplicated file descriptors
    exec 3>&- 4>&-

    # Restore stty settings if they were saved
    if [[ -n "${orig_stty:-}" ]]; then
        stty "$orig_stty"
    fi

    if [[ $exit_code -eq 0 ]]; then
        printf "🎉 Script completed successfully."
    else
        printf "\n⚠️ Script exited with code $exit_code."
    fi

    # Perform existing sudoers cleanup
    if [[ -n "${SUDOERS_FILE:-}" ]]; then
        if [[ -f "$SUDOERS_FILE" ]]; then
            printf "\n🗑️ Removing sudoers file at '$SUDOERS_FILE'..."
            sudo rm -f "$SUDOERS_FILE" 2>/dev/null && printf "\n🗑️ Sudoers file removed."
        else
            printf "\nℹ️ Sudoers file '$SUDOERS_FILE' does not exist. No removal needed."
        fi

        printf "\n🔒 Revoking sudo access..."
        sudo -k && printf "\n🔒 Sudo access revoked."

        # Reset the SUDOERS_SETUP_DONE flag
        export SUDOERS_SETUP_DONE=0
    else
        printf "\n🔍 Debug: SUDOERS_FILE is not set."
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
# Description: Initializes environment variables and FAILS FAST on
#              known-incompatible platforms for Homebrew.
# -----------------------------------------------
func_initialize_env_vars() {
    local arch os
    arch=$(uname -m)
    os=$(uname -s)

    USERNAME=$(id -un)
    USERGROUP=$(id -gn)
    ROOTGROUP=$(id -gn root | awk '{print $1}')  # Primary group only

    # ------------------------------------------------------------
    # HARD BLOCK: Unsupported CPU architectures (Homebrew limit)
    # ------------------------------------------------------------
    case "$arch" in
        x86_64|aarch64)
            # Supported by Homebrew on Linux
            ;;
        arm64)
            # macOS Apple Silicon (handled under Darwin)
            ;;
        *)
            echo "❌ Unsupported architecture: $arch"
            echo "Homebrew supports ONLY:"
            echo "  - x86_64 (Intel 64-bit)"
            echo "  - aarch64 / arm64 (ARM64)"
            echo ""
            echo "32-bit architectures (armv7, armv6, i386, etc.) are permanently unsupported."
            echo "This is a Homebrew limitation, not a bug in this installer."
            exit 1
            ;;
    esac

    # ------------------------------------------------------------
    # OS detection + Homebrew root
    # ------------------------------------------------------------
    if [[ "$os" == "Darwin" ]]; then
        DARWIN=1

        if [[ "$arch" == "arm64" ]]; then
            # Apple Silicon macOS
            HOMEBREW_PATH="/opt/homebrew"
        else
            # Intel macOS
            HOMEBREW_PATH="/usr/local"
        fi

    elif [[ "$os" == "Linux" ]]; then
        DARWIN=0

        # Linuxbrew root (Synology / generic Linux)
        HOMEBREW_PATH="/home/linuxbrew/.linuxbrew"

    else
        echo "❌ Unsupported operating system: $os"
        exit 1
    fi

    # ------------------------------------------------------------
    # Export authoritative environment
    # ------------------------------------------------------------
    export DARWIN HOMEBREW_PATH USERNAME USERGROUP ROOTGROUP
}

# -----------------------------------------------
# Function: get_minimal_baseline
# Description: Returns the minimal baseline packages for the current OS
# -----------------------------------------------
get_minimal_baseline() {
  if [[ $DARWIN -eq 0 ]]; then
    # Synology/Linux baseline
    echo "binutils glibc gcc git ruby python3 zsh yq"
  else
    # macOS baseline - without zsh (already included in macOS)
    echo "git yq ruby python3 coreutils findutils gnu-sed grep gawk"
  fi
}



# -----------------------------------------------
# Function: install_brew_and_packages
# Description: Installs Homebrew and necessary packages based on the operating system.
# -----------------------------------------------
install_brew_and_packages() {
    echo "Initializing environment variables..."
    func_initialize_env_vars
    if [[ $? -ne 0 ]]; then
        echo "Failed to initialize environment variables."
        return 1
    fi

    if [[ $DARWIN == 0 ]]; then 
        echo "System detected as LINUX"
    fi
    if [[ $DARWIN == 1 ]]; then 
        echo "System detected as DARWIN (macOS)"
    fi
    
    echo "Using HOMEBREW_PATH=$HOMEBREW_PATH"

    # DSM/Synology: ensure large-temp on /home before any brew calls
    if [[ $DARWIN -eq 0 ]]; then
        export HOMEBREW_TEMP="${HOMEBREW_TEMP:-$HOME/tmp}"
        export TMPDIR="${TMPDIR:-$HOMEBREW_TEMP}"
        mkdir -p "$HOMEBREW_TEMP" || {
            echo "❌ Failed to create $HOMEBREW_TEMP for brew temporary files." >&2
            return 1
        }
    fi

    # Remove Homebrew git environment variable if git is not executable
    if [[ ! -x "$HOMEBREW_PATH/bin/git" ]]; then
        unset HOMEBREW_GIT_PATH
        echo "Unset HOMEBREW_GIT_PATH because git is not executable in HOMEBREW_PATH."
    fi

    # Install Homebrew if it's not already installed
    if ! command -v brew >/dev/null 2>&1; then
        echo "Homebrew not found. Installing Homebrew..."
        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" 2> /dev/null | sed '/==> Next steps:/,/^$/d'
        if [[ $? -ne 0 ]]; then
            echo "Homebrew installation failed."
            return 1
        fi
    else
        echo "Homebrew is already installed. Proceeding..."
    fi

    # Initialize Homebrew environment
    if [[ -x "$HOMEBREW_PATH/bin/brew" ]]; then
        eval "$("$HOMEBREW_PATH/bin/brew" shellenv)"
        echo "Homebrew environment initialized."
    else
        echo "Homebrew executable not found at $HOMEBREW_PATH/bin/brew."
        return 1
    fi

    # Increase the maximum number of open file descriptors
    ulimit -n 2048
    echo "Set ulimit -n to 2048."

    # Use get_minimal_baseline to get the package list
    echo "Preparing to install minimal baseline packages for the system..."
    IFS=' ' read -ra PACKAGES <<< "$(get_minimal_baseline)"

    # Define the profile template path based on OS
    if [[ $DARWIN -eq 0 ]]; then
        PROFILE_TEMPLATE="./profile-templates/synology-profile-template"
    elif [[ $DARWIN -eq 1 ]]; then
        PROFILE_TEMPLATE="./profile-templates/macos-profile-template"
    else
        echo "Invalid DARWIN value: $DARWIN"
        return 1
    fi

    # Install each package individually from the PACKAGES array
    echo "Starting package installations..."
    for pkg in "${PACKAGES[@]}"; do
        brew install --quiet "$pkg" 2> /dev/null
        if [[ $? -ne 0 ]]; then
            echo "Failed to install $pkg."
            return 1
        else
            echo "Installed $pkg."
        fi
    done

    # Upgrade existing packages
    echo "Upgrading Homebrew packages..."
    brew upgrade --quiet 2> /dev/null
    if [[ $? -ne 0 ]]; then
        echo "Failed to upgrade Homebrew packages."
        return 1
    else
        echo "Upgraded Homebrew packages."
    fi

    # Create or update the appropriate profile file with Homebrew paths
    if [[ -f "$PROFILE_TEMPLATE" ]]; then
        echo "Creating profile file from template..."
        profile_filled=$(<"$PROFILE_TEMPLATE")
        profile_filled="${profile_filled//\$HOMEBREW_PATH/$HOMEBREW_PATH}"
        if [[ $DARWIN -eq 0 ]]; then
            echo "$profile_filled" > ~/.profile
            echo "Updated ~/.profile with Homebrew paths."
            source ~/.profile 2>/dev/null || true
        elif [[ $DARWIN -eq 1 ]]; then
            echo "$profile_filled" > ~/.zprofile
            echo "Updated ~/.zprofile with Homebrew paths."
            source ~/.zprofile
        fi
    else
        echo "Profile template '$PROFILE_TEMPLATE' not found."
        return 1
    fi

    echo "Homebrew and packages installation completed successfully."
}

func_git_commit_check() {
  # Show commit if we are in a git repo; otherwise skip quietly
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # Get short commit hash (fallback to unknown)
    if rev_short=$(git rev-parse --short HEAD 2>/dev/null); then
      echo "${INFO} Git Commit: ${rev_short}"
    else
      echo "${INFO} Git Commit: (unknown)"
    fi

    # Show current branch if possible
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
    if [[ -n "$branch" && "$branch" != "HEAD" ]]; then
      echo "${INFO} Branch: ${branch}"
    else
      echo "${INFO} Branch: (detached or unknown)"
    fi
  else
    echo "${INFO} Not a git repository; skipping commit info."
  fi
}

