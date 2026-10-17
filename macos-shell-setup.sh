#!/bin/bash
# Prepare the usable shell without installing formulas or running providers.
set -e
umask 077
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/functions.sh"
func_initialize_env_vars
[[ "$DARWIN" == 1 ]] || { echo "Shell preparation is macOS-only." >&2; exit 1; }
CONFIG=${1:-$SCRIPT_DIR/config.yaml}
[[ -f "$CONFIG" ]] || { echo "Config not found: $CONFIG" >&2; exit 1; }
func_bootstrap_yq
yq eval '.' "$CONFIG" >/dev/null

# macOS Git and zsh work before their Homebrew replacements are available.
command -v git >/dev/null
export RUNZSH=no CHSH=no ZSH_DISABLE_AUTO_UPDATE=true DISABLE_UPDATE_PROMPT=true
OMZ_DIR="$HOME/.oh-my-zsh"
if [[ ! -f "$OMZ_DIR/oh-my-zsh.sh" ]]; then
    if [[ -e "$OMZ_DIR" ]]; then
        echo "Incomplete Oh My Zsh directory: $OMZ_DIR. Preserving it; repair or move it before retrying." >&2
        exit 1
    fi
    git clone --depth=1 -- https://github.com/ohmyzsh/ohmyzsh.git "$OMZ_DIR"
fi

plugins="git web-search"
theme=""
entries=$(yq eval -r '.plugins // {} | to_entries[] | select(.value.action == "install") | [.key, .value.directory, .value.url] | @tsv' "$CONFIG")
while IFS=$'\t' read -r name directory url; do
    [[ -n "$name" ]] || continue
    directory=${directory/#\~/$HOME}
    case "$directory" in "$OMZ_DIR/custom/plugins/"*|"$OMZ_DIR/custom/themes/"*) ;; *) continue ;; esac
    # These names enter a zsh assignment; only direct shell plugin paths qualify.
    [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || { echo "Invalid shell plugin name: $name" >&2; exit 1; }
    [[ "$directory" == "$OMZ_DIR/custom/plugins/$name" || "$directory" == "$OMZ_DIR/custom/themes/$name" ]] || exit 1
    if [[ ! -d "$directory" ]]; then
        mkdir -p "$(dirname "$directory")"
        git clone --depth=1 -- "$url" "$directory"
    fi
    if [[ "$directory" == "$OMZ_DIR/custom/plugins/$name" ]]; then plugins="$plugins $name"; fi
    if [[ "$name" == powerlevel10k && "$directory" == "$OMZ_DIR/custom/themes/$name" ]]; then
        [[ -f "$directory/powerlevel10k.zsh-theme" ]] || exit 1
        theme='powerlevel10k/powerlevel10k'
        [[ -f "$HOME/.p10k.zsh" ]] || cp "$SCRIPT_DIR/profile-templates/p10k-profile-template" "$HOME/.p10k.zsh"
    fi
done <<< "$entries"

temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
zshrc="$HOME/.zshrc"
[[ -f "$zshrc" ]] || touch "$zshrc"
cat > "$temporary/block" <<EOF
# >>> Synology-Homebrew shell preparation >>>
export ZSH="\$HOME/.oh-my-zsh"
export ZSH_DISABLE_AUTO_UPDATE=true
export DISABLE_UPDATE_PROMPT=true
zstyle ':omz:update' mode disabled
plugins=($plugins)
EOF
[[ -z "$theme" ]] || printf 'ZSH_THEME="%s"\n' "$theme" >> "$temporary/block"
echo '# <<< Synology-Homebrew shell preparation <<<' >> "$temporary/block"

# Replace only our settings block, before the existing OMZ source statement.
awk '
 /^# >>> Synology-Homebrew shell preparation >>>$/ {skip=1; next}
 /^# <<< Synology-Homebrew shell preparation <<<$/{skip=0; next}
 /^# >>> Synology-Homebrew package integrations >>>$/ {skip=1; next}
 /^# <<< Synology-Homebrew package integrations <<<$/{skip=0; next}
 !skip {print}
' "$zshrc" > "$temporary/base"
if ! grep -qE '^[[:space:]]*source[[:space:]].*oh-my-zsh\.sh' "$temporary/base"; then
    printf '\nsource "$ZSH/oh-my-zsh.sh"\n' >> "$temporary/base"
fi
awk -v block="$temporary/block" '
 /^[[:space:]]*source[[:space:]].*oh-my-zsh\.sh/ && !inserted {
   while ((getline line < block)>0) print line; close(block); inserted=1
 }
 {print}
' "$temporary/base" > "$temporary/ready"
if [[ -n "$theme" ]] && ! grep -qF 'source ~/.p10k.zsh' "$temporary/ready"; then
    printf '\n[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh\n' >> "$temporary/ready"
fi
echo '# >>> Synology-Homebrew package integrations >>>' >> "$temporary/ready"
aliases=$(yq eval -r '(.packages + .plugins) | to_entries[] | select(.value.action == "install") | .value.aliases | select(tag == "!!map") | to_entries[] | "\(.key)=\(.value)"' "$CONFIG")
while IFS='=' read -r name value; do
    [[ -n "$name" ]] || continue
    [[ "$name" =~ ^[A-Za-z0-9_.-]+$ ]] || exit 1
    command_name=${value%% *}
    [[ "$command_name" =~ ^[A-Za-z0-9_./-]+$ ]] || continue
    printf 'if command -v %q >/dev/null 2>&1; then alias %q; fi\n' "$command_name" "$name=$value" >> "$temporary/ready"
done <<< "$aliases"
evaluations=$(yq eval -r '(.packages + .plugins) | to_entries[] | select(.value.action == "install") | .value.eval[]' "$CONFIG")
while IFS= read -r expression; do
    [[ -n "$expression" ]] || continue
    command_name=${expression%% *}
    [[ "$command_name" =~ ^[A-Za-z0-9_./-]+$ ]] || continue
    printf 'if command -v %q >/dev/null 2>&1' "$command_name" >> "$temporary/ready"
    # Apple's Perl exists before the local::lib provider does.
    if [[ "$command_name" == perl && "$expression" == *local::lib* ]]; then
        printf ' && perl -Mlocal::lib -e 1 >/dev/null 2>&1' >> "$temporary/ready"
    fi
    printf '; then eval "$(%s 2>/dev/null)"; fi\n' "$expression" >> "$temporary/ready"
done <<< "$evaluations"
echo '# <<< Synology-Homebrew package integrations <<<' >> "$temporary/ready"
/bin/zsh -n "$temporary/ready"
if ! cmp -s "$zshrc" "$temporary/ready"; then
    [[ -f "$zshrc.synology-homebrew-before-shell" ]] || cp -p "$zshrc" "$zshrc.synology-homebrew-before-shell"
    cat "$temporary/ready" > "$zshrc"
fi
func_ensure_zsh_function_path_guard "$zshrc"
chmod -R go-w "$OMZ_DIR"
echo "Shell ready: Oh My Zsh, selected shell plugins and theme. Existing shell settings and Powerlevel10k profile retained."
echo "Package aliases/integrations activate when their commands are available. Package themes and Neovim providers finish after the queue."
