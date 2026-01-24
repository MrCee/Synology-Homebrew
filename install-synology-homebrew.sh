#!/bin/bash

# -----------------------------------------------------------------------------
# Synology-Homebrew Installer (DROP-IN, FIXED ENDING + OMZ/P10K GUARANTEE)
#
# GUARANTEES (authoritative):
# - NEVER allow Oh My Zsh to self-update or prompt during install
# - NEVER let OMZ auto-run zsh during install (we control final exec)
# - ALLOWED: change shell at the END by exec into zsh (transport experience)
# - Cleanup (sudoers revoke) happens ONCE and BEFORE we exec into zsh
# - Final user-visible line is:
#     "🚀 You will now be transported to zsh..."
#   then zsh launches and Powerlevel10k loads from ~/.zshrc
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Installer safety: make OMZ non-interactive ALWAYS during installer runtime
# -----------------------------------------------------------------------------
export ZSH_DISABLE_AUTO_UPDATE=true
export DISABLE_AUTO_UPDATE=true
export DISABLE_UPDATE_PROMPT=true
export RUNZSH=no
export CHSH=no

DEBUG=0
[[ $DEBUG == 1 ]] && echo "DEBUG mode on with strict -euo pipefail error handling" && set -euo pipefail

# Define icons for better readability
INFO="ℹ️"
SUCCESS="✅"
WARNING="⚠️"
ERROR="❌"
TOOLS="🛠️"
REMOVE="🗑️"
REVOCATION="🔒"

SCRIPT_PATH=$(realpath "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")

# Change to the script directory
cd "$SCRIPT_DIR" || { echo "Failed to change directory to $SCRIPT_DIR" >&2; exit 1; }
echo "Working directory: $(pwd)"

# Source the functions file
source "./functions.sh"

# Set the path to your log file
LOG_FILE="./logfile.log"

# Initialize logging
func_setup_logging "$LOG_FILE"

# Initialize environment variables
func_initialize_env_vars

# Show env variables
echo "DARWIN: $DARWIN"
echo "HOMEBREW_PATH: $HOMEBREW_PATH"
echo "USERNAME: $USERNAME"
echo "USERGROUP: $USERGROUP"
echo "ROOTGROUP: $ROOTGROUP"

# -----------------------------------------------------------------------------
# Cleanup guard: ensure cleanup runs ONCE even if triggered multiple ways.
# IMPORTANT:
# - We want sudoers removed BEFORE we launch interactive zsh.
# - But we must not run cleanup twice (duplication + confusing output).
# -----------------------------------------------------------------------------
_CLEANUP_RAN=0
cleanup_once() {
  local code="${1:-0}"
  if [[ "$_CLEANUP_RAN" -eq 1 ]]; then
    return 0
  fi
  _CLEANUP_RAN=1
  func_cleanup_exit "$code"
}

# Set Trap for EXIT to Handle Normal Cleanup (guarded)
trap 'code=$?; cleanup_once "$code"' EXIT

# Set Trap for Interruption Signals to Handle Cleanup (guarded)
trap 'cleanup_once 130' INT TERM HUP QUIT ABRT ALRM PIPE

# Setup sudoers file
func_sudoers

# Check if sudoers setup was successful before proceeding
if [[ "${SUDOERS_SETUP_DONE:-0}" -ne 1 ]]; then
  echo "Sudoers setup was not completed successfully. Exiting." >&2
  exit 1
fi

[[ $DEBUG == 1 ]] && echo "Debug: SUDOERS_FILE is set to '$SUDOERS_FILE'"

# Check if the script is being run as root
if [[ "$EUID" -eq 0 ]]; then
  echo "This script should not be run as root. Run it as a regular user, although we will need root password in a second..." >&2
  exit 1  # Triggers cleanup via EXIT trap
fi

# Check prerequisites of this script
error=false
git_install_flag=false

if [[ $DARWIN == 0 ]]; then
  # Check if Synology Homes is enabled
  if [[ ! -d /var/services/homes/$(whoami) ]]; then
    echo "Synology Homes has NOT been enabled. Please enable in DSM Control Panel >> Users & Groups >> Advanced >> User Home." >&2
    error=true
  fi

  # Check if Git is installed
  if ! git --version > /dev/null 2>&1; then
    echo "Git not installed. Adding the SynoCommunity repository..."

    # Add SynoCommunity feed if not present
    if [[ ! -f /usr/syno/etc/packages/feeds ]]; then
      echo "Adding SynoCommunity feed..."
      echo '[{"feed":"https://packages.synocommunity.com/","name":"SynoCommunity"}]' | sudo tee /usr/syno/etc/packages/feeds > /dev/null
      sudo chmod 755 /usr/syno/etc/packages/feeds
    fi

    # Append to feeds if SynoCommunity is missing
    if ! sudo grep -q "https://packages.synocommunity.com/" /usr/syno/etc/packages/feeds; then
      echo "Appending SynoCommunity feed..."
      echo '[{"feed":"https://packages.synocommunity.com/","name":"SynoCommunity"}]' | sudo tee -a /usr/syno/etc/packages/feeds > /dev/null
    fi

    # Attempt to install Git
    echo "Attempting to install Git..."
    sudo synopkg install_from_server Git
    git_install_flag=true

    # Confirm if Git was installed successfully
    if git --version > /dev/null 2>&1; then
      echo "✅ Git has been installed"
    else
      echo "❌ Git could not be installed. Please install it manually from SynoCommunity in Package Centre (https://packages.synocommunity.com)." >&2
      error=true
    fi
  else
    echo "✅ Git is already installed."
  fi

  # If any error occurred, exit with status 1 (triggers cleanup)
  if $error; then
    echo "❌ Exiting due to errors."
    exit 1
  fi
fi # end DARWIN=0

# Define the location of YAML
CONFIG_YAML_PATH="./config.yaml"

# Only touch YAML in Advanced mode
YAML_READY=0

# Function to display the menu
display_menu() {
  cat <<EOF
Select your install type:

1) Minimal Install: This will provide the homebrew basics, ignore packages in config.yaml, leaving the rest to you.
   ** You can also use this option to uninstall packages in config.yaml installed by option 2 by running the script again.

2) Advanced Install: Full setup includes packages in config.yaml
   ** Recommended if you want to get started with Neovim or install some of the great packages listed.

Enter selection:
EOF
}

[[ $DEBUG == 0 ]] && clear
while true; do
  display_menu
  read -r selection

  case "$selection" in
    1|2) break ;;
    *) echo "Invalid selection. Please enter 1 or 2."
       read -r -p "Press Enter to continue..." ;;
  esac
done

# Derive install mode (authoritative)
if [[ "$selection" -eq 1 ]]; then
  INSTALL_MODE="minimal"
else
  INSTALL_MODE="advanced"
fi
export INSTALL_MODE
echo "INSTALL_MODE=$INSTALL_MODE"

[[ $DEBUG == 0 ]] && clear

# Advanced-only: require YAML file exists (pre-check)
if [[ "$INSTALL_MODE" == "advanced" && ! -f "$CONFIG_YAML_PATH" ]]; then
  echo "config.yaml not found in this directory" >&2
  exit 1  # Triggers cleanup
fi

if [[ $DARWIN == 0 ]]; then

  # Retrieve DSM OS Version without Percentage Sign
  source /etc.defaults/VERSION
  clean_smallfix="${smallfixnumber%\%}"
  printf 'DSM Version: %s-%s Update %s\n' "$productversion" "$buildnumber" "$clean_smallfix"

  # Retrieve CPU Model Name
  echo -n "CPU: "
  awk -F': ' '/model name/ {print $2; exit}' /proc/cpuinfo

  # Retrieve System Architecture
  echo -n "Architecture: "
  uname -m
  echo

  # Convert versions into comparable integers
  current_version=$((majorversion * 100 + minorversion))
  min_supported_version=$((7 * 100 + 1))   # DSM 7.1
  recommended_version=$((7 * 100 + 2))     # DSM 7.2+

  if [[ "$current_version" -lt "$min_supported_version" ]]; then
    echo "❌ Your DSM version is too old."
    echo "   Minimum supported version is DSM 7.1."
    exit 1
  fi

  if [[ "$current_version" -lt "$recommended_version" ]]; then
    echo "⚠️  DSM $productversion detected."
    echo "   DSM 7.2+ is recommended and fully validated."
    echo "   DSM 7.1 is allowed but may have minor limitations."
    echo ""
  fi

  MODE_LABEL="Advanced Install"
  [[ "$INSTALL_MODE" == "minimal" ]] && MODE_LABEL="Minimal Install"
  echo "Starting $MODE_LABEL..."

  func_git_commit_check

  export HOMEBREW_NO_ENV_HINTS=1
  export HOMEBREW_NO_AUTO_UPDATE=1

  # Install ldd file script
  sudo install -m 755 /dev/stdin /usr/bin/ldd <<EOF
#!/bin/bash
[[ \$("/usr/lib/libc.so.6") =~ version\ ([0-9]\.[0-9]+) ]] && echo "ldd \${BASH_REMATCH[1]}"
EOF

  # Install os-release file script
  sudo install -m 755 /dev/stdin /etc/os-release <<EOF
#!/bin/bash
echo "PRETTY_NAME=\"\$(source /etc.defaults/VERSION && printf '%s %s-%s Update %s' \"\$os_name\" \"\$productversion\" \"\$buildnumber\" \"\$smallfixnumber\")\""
EOF

  # Ensure /home exists
  [[ ! -d /home ]] && sudo mkdir /home

  # Only mount if it's not already a mountpoint
  if ! grep -qs ' /home ' /proc/mounts; then
    sudo mount -o bind "$(readlink -f /var/services/homes)" /home
  fi

  # Permission fixes
  sudo chown root:root /home
  sudo chmod 775 /home

  if [[ -d /home/linuxbrew ]]; then
    sudo chown root:root /home/linuxbrew
    sudo chmod 775 /home/linuxbrew
  fi
fi # end DARWIN=0

[[ $DARWIN == 1 ]] && func_git_commit_check

# Synology-only: keep bottle extraction off md0 for this run (no persistent env)
if [[ $DARWIN == 0 ]]; then
  export HOMEBREW_TEMP="${HOMEBREW_TEMP:-$HOME/tmp}"
  export TMPDIR="${TMPDIR:-$HOMEBREW_TEMP}"
  mkdir -p "$HOMEBREW_TEMP" || true
fi

install_brew_and_packages

echo "--------------------------PATH SET-------------------------------"
echo "$PATH"
echo "-----------------------------------------------------------------"

# -------------------- MINIMAL prune prompt (leaf-only, safe) --------------------
if [[ "$INSTALL_MODE" == "minimal" ]]; then
  echo "Minimal mode: baseline installed. Checking for extras beyond minimal…"

  if [[ $DARWIN -eq 0 ]]; then
    MIN_BASELINE=(binutils glibc gcc git ruby python3 zsh yq)
  else
    MIN_BASELINE=(git yq ruby python3 coreutils findutils gnu-sed grep gawk zsh)
  fi

  EXPLICITLY_INSTALLED=()
  while IFS= read -r line; do
    EXPLICITLY_INSTALLED+=("$line")
  done < <(brew leaves 2>/dev/null || true)

  EXTRAS=()
  for p in "${EXPLICITLY_INSTALLED[@]}"; do
    if ! printf '%s\n' "${MIN_BASELINE[@]}" | grep -Fxq "$p"; then
      EXTRAS+=("$p")
    fi
  done

  if (( ${#EXTRAS[@]} > 0 )); then
    echo "Found ${#EXTRAS[@]} additional formulas beyond minimal baseline:"
    printf '  - %s\n' "${EXTRAS[@]}"

    read -r -p "Prune these back to minimal now? [y/N]: " REPLY
    case "$REPLY" in
      [Yy]*)
        for pkg in "${EXTRAS[@]}"; do
          echo "🔄 Uninstalling: $pkg"
          brew uninstall --quiet "$pkg" || echo "⚠️ Could not uninstall $pkg"
        done
        ;;
      *) echo "Keeping existing formulas (no prune).";;
    esac
  else
    echo "Already at minimal baseline. ✅"
  fi
fi
# -------------------- end MINIMAL prune prompt --------------------

# Advanced only: validate & load YAML
if [[ "$INSTALL_MODE" == "advanced" ]]; then
  # Clean/escape edge cases in YAML (your two func_sed lines)
  printf "🧩 YAML escape pass 1: fixing unescaped backslashes → "
  func_sed 's/([^\\])\\([^\\"])/\1\\\\\2/g' "$CONFIG_YAML_PATH"
  printf "🧩 YAML escape pass 2: fixing embedded quotes → "
  func_sed 's/(^.*:[[:space:]]"[^\"]*)("[^"]*)(".*"$)/\1\\\2\\\3/g' "$CONFIG_YAML_PATH"

  if ! yq eval '.' "$CONFIG_YAML_PATH" > /dev/null 2>&1; then
    printf "Error: The YAML file '%s' is invalid.\n" "$CONFIG_YAML_PATH" >&2
    exit 1
  else
    printf "The YAML file '%s' is valid.\n" "$CONFIG_YAML_PATH"
  fi

  CONFIG_YAML=$(<"$CONFIG_YAML_PATH")
  YAML_READY=1
fi

if [[ $DARWIN == 0 ]]; then
  ruby_path=$(command -v ruby)
  if [[ "$ruby_path" != *"linuxbrew"* ]]; then
    echo "ruby is not linked via Homebrew. Linking ruby..."
    brew link --overwrite ruby
    if [[ $? -eq 0 ]]; then
      echo "ruby has been successfully linked via Homebrew."
    else
      echo "Failed to link ruby via Homebrew." >&2
      exit 1
    fi
  else
    echo "ruby is linked via Homebrew."
  fi
fi # end DARWIN=0

# Arrays to store summary messages
installed_packages=()
uninstalled_packages=()
skipped_packages=()
failed_packages=()

# Define color codes (optional for enhanced readability)
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

get_base_package() {
  local full_package="$1"
  local base_package="${full_package##*/}"
  echo "$base_package"
}

process_package() {
  local package="$1"
  local action="$2"
  local base_package
  base_package=$(get_base_package "$package")

  if brew list --formula -1 | grep -Fxq "$base_package"; then
    case "$action" in
      uninstall)
        echo -e "🔄 ${YELLOW}${base_package}${NC}: Uninstalling..."
        if brew uninstall --quiet "$base_package"; then
          uninstalled_packages+=("$base_package")
        else
          echo -e "${RED}❌ Failed to uninstall ${base_package}.${NC}"
          failed_packages+=("$base_package (uninstall)")
        fi
        ;;
      skip)
        echo -e "⏭️ ${YELLOW}${base_package}${NC}: Skipping (flagged to skip)"
        skipped_packages+=("$base_package")
        ;;
      install)
        echo -e "${GREEN}✅ ${base_package}${NC}: Already installed"
        ;;
      *)
        echo -e "${RED}⚠️ ${base_package}${NC}: Invalid action ('${action}')"
        failed_packages+=("$base_package (invalid action)")
        ;;
    esac
  else
    case "$action" in
      install)
        echo -e "🛠️ ${GREEN}${base_package}${NC}: Installing..."
        if brew install --quiet "$base_package" 2>&1 | sed '/==> Next steps:/,/^$/d; /By default/d'; then
          installed_packages+=("$base_package")
        else
          echo -e "${RED}❌ Error installing ${base_package}.${NC}"
          failed_packages+=("$base_package (install)")
        fi
        ;;
      uninstall)
        echo -e "🚫 ${YELLOW}${base_package}${NC}: Not installed but flagged for uninstall"
        skipped_packages+=("$base_package")
        ;;
      skip)
        echo -e "⏭️ ${YELLOW}${base_package}${NC}: Skipping (flagged to skip)"
        skipped_packages+=("$base_package")
        ;;
      *)
        echo -e "${RED}⚠️ ${base_package}${NC}: Invalid action ('${action}')"
        failed_packages+=("$base_package (invalid action)")
        ;;
    esac
  fi
}

main() {
  if ! command -v yq &> /dev/null; then
    echo -e "${RED}yq is not installed. Please install yq to proceed.${NC}"
    exit 1
  fi

  packages_array=()
  actions_array=()

  while IFS= read -r package; do
    packages_array+=("$package")
    action=$(yq eval -r ".packages[\"$package\"].action" <<< "$CONFIG_YAML")
    actions_array+=("$action")
  done < <(yq eval -r '.packages | keys | .[]' <<< "$CONFIG_YAML")

  if [[ ${#packages_array[@]} -eq 0 ]]; then
    echo -e "${YELLOW}No packages found in config.yaml.${NC}"
    return 0
  fi

  for idx in "${!packages_array[@]}"; do
    package="${packages_array[$idx]}"
    action="${actions_array[$idx]}"
    process_package "$package" "$action"
  done

  echo -e "\n📋 ${GREEN}Summary:${NC}"

  if [[ ${#installed_packages[@]} -ne 0 ]]; then
    echo -e "\n✅ Installed Packages:"
    for pkg in "${installed_packages[@]}"; do
      echo "  - $pkg"
    done
  fi

  if [[ ${#uninstalled_packages[@]} -ne 0 ]]; then
    echo -e "\n🗑️ Uninstalled Packages:"
    for pkg in "${uninstalled_packages[@]}"; do
      echo "  - $pkg"
    done
  fi

  if [[ ${#skipped_packages[@]} -ne 0 ]]; then
    echo -e "\n⏭️ Skipped Packages:"
    for pkg in "${skipped_packages[@]}"; do
      echo "  - $pkg"
    done
  fi

  if [[ ${#failed_packages[@]} -ne 0 ]]; then
    echo -e "\n❌ Failed Actions:"
    for pkg in "${failed_packages[@]}"; do
      echo "  - $pkg"
    done
  fi

  echo -e "\n✅ YAML package processing completed."
}

# Execute YAML-driven main only in Advanced
if [[ "$INSTALL_MODE" == "advanced" && "$YAML_READY" -eq 1 ]]; then
  main
fi

# Create the symlinks
sudo ln -sf "$HOMEBREW_PATH/bin/python3" "$HOMEBREW_PATH/bin/python"
sudo ln -sf "$HOMEBREW_PATH/bin/pip3" "$HOMEBREW_PATH/bin/pip"
[[ $DARWIN == 0 ]] && sudo ln -sf "$HOMEBREW_PATH/bin/gcc" "$HOMEBREW_PATH/bin/cc"
[[ $DARWIN == 0 ]] && sudo ln -sf "$HOMEBREW_PATH/bin/zsh" /bin/zsh
printf "\nFinished creating symlinks\n"

if [[ "$INSTALL_MODE" == "advanced" && "$YAML_READY" -eq 1 ]]; then
  if [[ $(yq eval -r '.packages.perl.action' <<< "$CONFIG_YAML") == "install" ]]; then
    if [[ $DARWIN == 0 ]]; then
      printf "\nFixing perl symlink..."
      sudo ln -sf "$HOMEBREW_PATH/bin/perl" /usr/bin/perl
    fi

    printf "\nSetting up permissions for perl environment..."
    sudo mkdir -p "$HOME/perl5" "$HOME/.cpan"
    sudo chown -R "$USERNAME:$ROOTGROUP" "$HOME/perl5" "$HOME/.cpan"
    sudo chmod -R 775 "$HOME/perl5" "$HOME/.cpan"

    printf "\nEnabling perl cpan with defaults and permission fix"
    PERL_MM_USE_DEFAULT=1 PERL_MM_OPT=INSTALL_BASE="$HOME/perl5" cpan local::lib

    eval "$(perl -I"$HOME/perl5/lib/perl5" -Mlocal::lib="$HOME/perl5")"
  fi
fi

# Check if additional Neovim packages should be installed
echo "-----------------------------------------------------------------"
if [[ "$INSTALL_MODE" == "advanced" && "$YAML_READY" -eq 1 ]]; then
  echo "-----------------------------------------------------------------"
  if [[ $(yq eval -r '.packages.neovim.action' <<< "$CONFIG_YAML") == "install" ]]; then
    echo "Calling ./install-neovim.sh for additional setup packages"
    temp_file=$(mktemp)
    printf '%s\n' "$CONFIG_YAML" > "$temp_file"
    ./install-neovim.sh "$temp_file"
    CONFIG_YAML=$(<"$temp_file")
    rm "$temp_file"
  else
    echo "SKIPPING: Neovim components as config.yaml install flag is set to false."
  fi
fi

# Read YAML and install/uninstall plugins
if [[ "$INSTALL_MODE" == "advanced" && "$YAML_READY" -eq 1 ]]; then
  yq eval -r '.plugins | to_entries[] | "\(.key) \(.value.action) \(.value.directory) \(.value.url)"' <<< "$CONFIG_YAML" \
    | while read -r plugin action directory url; do
        directory=${directory/#\~/$HOME}
        if [[ "$action" == "install" && ! -d "$directory" ]]; then
          echo "$plugin is not installed, cloning..."
          git clone "$url" "$directory"
        elif [[ "$action" == "install" && -d "$directory" ]]; then
          echo "$plugin is already installed."
        elif [[ "$action" == "uninstall" && -d "$directory" ]]; then
          echo "$plugin action is set to uninstall in config.yaml. Removing plugin directory..."
          rm -rf "$directory"
        elif [[ "$action" == "uninstall" && ! -d "$directory" ]]; then
          echo "$plugin is set to uninstall and is not installed. No action needed."
        elif [[ "$action" == "skip" ]]; then
          echo "$plugin action is set to skip in config.yaml. No action will be taken."
        else
          echo "Invalid action for $plugin in config.yaml. No action will be taken."
        fi
      done
fi

# -----------------------------------------------------------------------------
# Advanced: GUARANTEE Oh My Zsh is installed (NO prompts, NO auto-run)
# We use git clone (idempotent) to avoid OMZ installer prompting/updating.
# -----------------------------------------------------------------------------
if [[ "$INSTALL_MODE" == "advanced" && "$YAML_READY" -eq 1 ]]; then
  OMZ_DIR="$HOME/.oh-my-zsh"
  OMZ_SH="$OMZ_DIR/oh-my-zsh.sh"

  if [[ ! -f "$OMZ_SH" ]]; then
    echo "Installing Oh My Zsh (non-interactive, git clone)..."
    rm -rf "$OMZ_DIR" 2>/dev/null || true
    git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$OMZ_DIR"
  else
    echo "Oh My Zsh already installed."
  fi

  # Ensure ~/.zshrc exists
  [[ -f "$HOME/.zshrc" ]] || touch "$HOME/.zshrc"

  # Ensure OMZ path + source line exist exactly once (safe, idempotent)
  if ! grep -qE '^[[:space:]]*export[[:space:]]+ZSH=' "$HOME/.zshrc" 2>/dev/null; then
    echo 'export ZSH="$HOME/.oh-my-zsh"' >> "$HOME/.zshrc"
  fi

  if ! grep -qE '^[[:space:]]*source[[:space:]].*oh-my-zsh\.sh' "$HOME/.zshrc" 2>/dev/null; then
    echo 'source "$ZSH/oh-my-zsh.sh"' >> "$HOME/.zshrc"
  fi

  # Also hard-disable prompts/updates at runtime (belt + suspenders)
  if ! grep -qE '^[[:space:]]*export[[:space:]]+ZSH_DISABLE_AUTO_UPDATE=' "$HOME/.zshrc" 2>/dev/null; then
    echo 'export ZSH_DISABLE_AUTO_UPDATE=true' >> "$HOME/.zshrc"
  fi
  if ! grep -qE '^[[:space:]]*export[[:space:]]+DISABLE_UPDATE_PROMPT=' "$HOME/.zshrc" 2>/dev/null; then
    echo 'export DISABLE_UPDATE_PROMPT=true' >> "$HOME/.zshrc"
  fi
fi

# -----------------------------------------------------------------------------
# Advanced: Ensure Powerlevel10k is the active OMZ theme (MUST be BEFORE OMZ source)
# This MUST occur before any script that might add/source oh-my-zsh.sh.
# -----------------------------------------------------------------------------
if [[ "$INSTALL_MODE" == "advanced" && "$YAML_READY" -eq 1 ]]; then
  if [[ $(yq eval -r '.plugins.powerlevel10k.action // "skip"' <<< "$CONFIG_YAML") == "install" ]]; then

    # Ensure p10k repo exists (in case plugin loop was skipped earlier)
    P10K_DIR="$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
    if [[ ! -d "$P10K_DIR" ]]; then
      echo "Powerlevel10k missing, cloning..."
      git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
    fi

    # Ensure theme is set and placed BEFORE OMZ source line
    if grep -qE '^[[:space:]]*source[[:space:]].*oh-my-zsh\.sh' "$HOME/.zshrc" 2>/dev/null; then
      echo "Activating Powerlevel10k theme (pre-OMZ)"
      sed -i.bak '
        /^ZSH_THEME=/d
        /^[[:space:]]*source[[:space:]].*oh-my-zsh\.sh/i\
ZSH_THEME="powerlevel10k/powerlevel10k"
      ' "$HOME/.zshrc"
    else
      echo "⚠️ Could not find OMZ source line in ~/.zshrc (theme not injected)."
    fi
  fi
fi

# Check if any zsh packages should be configured
echo "-----------------------------------------------------------------"
if [[ "$INSTALL_MODE" == "advanced" && "$YAML_READY" -eq 1 ]]; then
  echo "-----------------------------------------------------------------"
  echo "Calling ./zsh_config.sh for additional zsh configuration"
  ./zsh_config.sh "$CONFIG_YAML"
fi

# Extract and filter alias commands directly from CONFIG_YAML
if [[ "$INSTALL_MODE" == "advanced" && "$YAML_READY" -eq 1 ]]; then
  alias_commands=$(yq eval -r '
    (.packages + .plugins)
    | to_entries[]
    | select(.value.aliases != [] and .value.action != "uninstall")
    | .value.aliases
    | to_entries[]
    | select(.key != "" and .value != "")
    | "\(.key)=\(.value)"
  ' <<< "$CONFIG_YAML" | grep -v "^=$")

  if [[ -n "$alias_commands" ]]; then
    while IFS='=' read -r key value; do
      value=$(printf '%s' "$value" | sed 's/"/\\"/g')
      formatted_alias="alias ${key}=\"${value}\""
      if ! grep -qF "$formatted_alias" "$HOME/.zshrc" 2>/dev/null; then
        echo "Adding alias command: $formatted_alias"
        echo "$formatted_alias" >> "$HOME/.zshrc"
      else
        echo "Alias already exists: $formatted_alias"
      fi
    done <<< "$alias_commands"
  else
    echo "No aliases to add."
  fi
fi

# Extract and filter eval commands directly from CONFIG_YAML
if [[ "$INSTALL_MODE" == "advanced" && "$YAML_READY" -eq 1 ]]; then
  eval_commands=$(yq eval -r '
    (.packages + .plugins)
    | to_entries[]
    | select(.value.eval != [] and .value.action != "uninstall")
    | .value.eval[]
  ' <<< "$CONFIG_YAML" | grep -v "^=$")

  if [[ -n "$eval_commands" ]]; then
    while IFS= read -r eval_command; do
      eval_command=$(printf '%s' "$eval_command" | sed 's/"/\\"/g')
      formatted_eval="eval \"\$($eval_command)\""
      if ! grep -qF "$formatted_eval" "$HOME/.zshrc" 2>/dev/null; then
        echo "Adding eval command: $formatted_eval"
        echo "$formatted_eval" >> "$HOME/.zshrc"
      else
        echo "Eval command already exists: $formatted_eval"
      fi
    done <<< "$eval_commands"
  else
    echo "No eval commands to add."
  fi
fi

###############################################################################
# FINAL TRANSPORT — COMPLETE CLEANUP THEN ZSH HANDOFF (KNOWN-GOOD)
###############################################################################

# 1) Perform full cleanup explicitly (sudoers, logs, permissions, etc.)
cleanup_once 0

# 2) Disable all traps so nothing fires again
trap - EXIT
trap - INT TERM HUP QUIT ABRT ALRM PIPE

# 3) Final installer message (last thing installer prints)
echo ""
echo "✨====================================================================✨"
echo "  🚀 You will now be transported to zsh..."
echo "✨====================================================================✨"
echo ""

# 4) Replace the installer process with zsh, attached to a real TTY
exec /bin/zsh -il </dev/tty >/dev/tty 2>&1
