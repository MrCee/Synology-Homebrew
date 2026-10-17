#!/bin/bash
# macOS-only persistent package queue. LaunchAgent runs as the login user.
set -u
umask 077

STATE_ROOT="$HOME/.local/share/synology-homebrew/background"
LABEL="com.mrcee.synology-homebrew.packages"
DOMAIN="gui/$(id -u)"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
WINDOW_LABEL="$LABEL.status"
WINDOW_PLIST="$HOME/Library/LaunchAgents/$WINDOW_LABEL.plist"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

ALLOW_SOURCE_BUILDS=0
queue_arguments=()
for queue_argument in "$@"; do
    if [[ "$queue_argument" == --allow-source-builds ]]; then
        ALLOW_SOURCE_BUILDS=1
    else
        queue_arguments+=("$queue_argument")
    fi
done
set -- "${queue_arguments[@]}"

set_status() {
    printf '%s\n' "$1" > "$JOB/status.tmp"
    mv "$JOB/status.tmp" "$JOB/status"
}

load_job() {
    [[ -f "$STATE_ROOT/latest" ]] || { echo "No macOS package queue has been created."; return 1; }
    JOB=$(cat "$STATE_ROOT/latest")
    case "$JOB" in "$STATE_ROOT"/jobs/*) ;; *) echo "Invalid queue path." >&2; return 1 ;; esac
    [[ -d "$JOB" ]]
}

worker_alive() {
    [[ -f "$JOB/lock/pid" ]] || return 1
    local pid command
    pid=$(cat "$JOB/lock/pid")
    case "$pid" in ''|*[!0-9]*) return 1 ;; esac
    # After a reboot, a new runner can reuse the saved PID of the old runner.
    [[ "$pid" != "$$" ]] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    command=$(ps -p "$pid" -o command= 2>/dev/null) || return 1
    [[ "$command" == *"$JOB/runner.sh"* ]]
}

queue_busy() {
    load_job >/dev/null || return 1
    worker_alive && return 0
    case "$(cat "$JOB/status")" in pending|running|interrupted|retry_wait|needs_attention|paused|stopping) return 0 ;; *) return 1 ;; esac
}

verify_queue() {
    [[ $# == 1 ]] || return 1
    load_job >/dev/null || return 1
    [[ "$(cat "$JOB/status")" == packages_ready ]] || return 1
    cmp -s "$1" "$JOB/config.yaml" || return 1
    local brew package
    brew=$(cat "$JOB/brew")
    [[ -x "$brew" ]] || return 1
    while IFS= read -r package; do
        "$brew" list --versions "$package" >/dev/null 2>&1 || return 1
    done < "$JOB/queue"
}

xml_escape() {
    local value="$1"
    value=${value//&/\&amp;}
    value=${value//</\&lt;}
    value=${value//>/\&gt;}
    value=${value//\"/\&quot;}
    printf '%s' "$value"
}

register_agent() {
    local job_xml window_mode="${1:-replace}"
    job_xml=$(xml_escape "$JOB")
    mkdir -p "$(dirname "$PLIST")" || return 1
    cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$LABEL</string>
<key>ProgramArguments</key><array><string>/bin/bash</string><string>$job_xml/runner.sh</string><string>run</string></array>
<key>RunAtLoad</key><true/>
<key>ProcessType</key><string>Background</string>
<key>LowPriorityIO</key><true/>
<key>AbandonProcessGroup</key><false/>
<key>ExitTimeOut</key><integer>5</integer>
<key>StandardOutPath</key><string>$job_xml/worker.log</string>
<key>StandardErrorPath</key><string>$job_xml/worker.log</string>
</dict></plist>
EOF
    # Only replace an idle service. Never terminate an active package install.
    if worker_alive; then return 0; fi
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    if ! launchctl bootstrap "$DOMAIN" "$PLIST"; then
        echo "Queue saved, but its LaunchAgent could not start. Run resume from this Mac's desktop login." >&2
        return 1
    fi
    if [[ "$window_mode" == preserve ]] && launchctl print "$DOMAIN/$WINDOW_LABEL" >/dev/null 2>&1; then
        # A retry can be requested by the window itself. Do not boot out its
        # process group (which also contains this short-lived resume command).
        launchctl kickstart "$DOMAIN/$WINDOW_LABEL" 2>/dev/null || true
    else
        register_window || echo "The worker is queued, but its status window could not open. Use the status command." >&2
    fi
}

register_window() {
    local job_xml
    job_xml=$(xml_escape "$JOB")
    mkdir -p "$(dirname "$WINDOW_PLIST")" || return 1
    cat > "$WINDOW_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$WINDOW_LABEL</string>
<key>ProgramArguments</key><array><string>/usr/bin/osascript</string><string>-l</string><string>JavaScript</string><string>$job_xml/status-window.js</string><string>$job_xml</string></array>
<key>RunAtLoad</key><true/>
<key>StandardOutPath</key><string>$job_xml/window.log</string>
<key>StandardErrorPath</key><string>$job_xml/window.log</string>
</dict></plist>
EOF
    launchctl bootout "$DOMAIN/$WINDOW_LABEL" 2>/dev/null || true
    launchctl bootstrap "$DOMAIN" "$WINDOW_PLIST"
}

show_status() {
    load_job || return 1
    local state
    state=$(cat "$JOB/status")
    if [[ "$state" == running ]] && ! worker_alive; then state=interrupted; fi
    echo "Package queue: $state"
    echo "Completed: $(wc -l < "$JOB/completed" | tr -d ' ') / $(wc -l < "$JOB/queue" | tr -d ' ')"
    [[ ! -s "$JOB/current" ]] || echo "Current/last package: $(cat "$JOB/current")"
    if [[ -s "$JOB/failures" ]]; then
        echo "Failed packages (resume retries these):"
        cat "$JOB/failures"
    fi
    echo "Log: $JOB/worker.log"
    echo "Config snapshot: $JOB/config.yaml"
    echo "Automatic resume: at this Mac user's next login (not before login)."
    [[ ! -f "$JOB/next-retry" ]] || echo "Next retry (Unix time): $(cat "$JOB/next-retry")"
    if [[ "$state" == packages_ready ]]; then
        if [[ -f "$JOB/allow-source-builds" ]]; then
            echo "Selected fallback packages are installed. No further package setup is required."
        else
            echo "Packages are installed. Full setup is pending: run the main installer and choose option 2."
        fi
    fi
}

checkpoint_installed() {
    local brew package
    brew=$(cat "$JOB/brew")
    : > "$JOB/completed.tmp"
    echo "Checking already installed formulas before starting the queue..."
    while IFS= read -r package; do
        if "$brew" list --versions "$package" >/dev/null 2>&1; then
            printf '%s\n' "$package" >> "$JOB/completed.tmp"
        fi
    done < "$JOB/queue"
    mv "$JOB/completed.tmp" "$JOB/completed"
}

prepare_queue() {
    [[ ( $# == 1 || ( $# == 2 && "$2" == --paused ) ) && -f "$1" ]] || { echo "Usage: bash background-packages.sh start config.yaml [--paused]" >&2; return 1; }
    if queue_busy; then
        echo "An unfinished queue already exists. Use status or resume instead." >&2
        return 1
    fi
    source "$SCRIPT_DIR/functions.sh"
    func_initialize_env_vars
    [[ "$DARWIN" == 1 && -x "$HOMEBREW_PATH/bin/brew" ]] || return 1
    eval "$("$HOMEBREW_PATH/bin/brew" shellenv)" || return 1
    func_bootstrap_yq || return 1
    yq eval '.' "$1" >/dev/null || return 1
    local jobs package candidates
    jobs=${SYNOBREW_BUILD_JOBS:-2}
    case "$jobs" in ''|*[!0-9]*|0) echo "SYNOBREW_BUILD_JOBS must be a positive integer." >&2; return 1 ;; esac
    mkdir -p "$STATE_ROOT/jobs" || return 1
    JOB=$(mktemp -d "$STATE_ROOT/jobs/job.XXXXXXXX") || return 1
    cp "$1" "$JOB/config.yaml" || return 1
    cp "$SCRIPT_DIR/background-packages.sh" "$JOB/runner.sh" || return 1
    cp "$SCRIPT_DIR/background-packages.sh" "$JOB/controller.sh" || return 1
    cp "$SCRIPT_DIR/macos-package-status.js" "$JOB/status-window.js" || return 1
    local queue_brew="$HOMEBREW_PATH/bin/brew"
    if [[ "$ALLOW_SOURCE_BUILDS" == 1 ]]; then
        printf 'yes\n' > "$JOB/allow-source-builds"
        # Use the preserved official symlink so the prefix remains /usr/local.
        [[ ! -x "$HOMEBREW_PATH/bin/brew.before-synobrew" ]] || queue_brew="$HOMEBREW_PATH/bin/brew.before-synobrew"
    fi
    printf '%s\n' "$queue_brew" > "$JOB/brew"
    printf '%s\n' "$jobs" > "$JOB/build-jobs"
    date +%s > "$JOB/started-at"
    printf '%s\n' "$SCRIPT_DIR" > "$JOB/repository"
    if [[ "$ALLOW_SOURCE_BUILDS" == 1 ]]; then
        : > "$JOB/candidates" # Last resort: only the specifically selected failures.
    else
        get_minimal_baseline | tr ' ' '\n' > "$JOB/candidates"
    fi
    candidates=$(yq eval -r '.packages | to_entries | .[] | select(.value.action == "install") | .key' "$JOB/config.yaml") || return 1
    printf '%s\n' "$candidates" >> "$JOB/candidates"
    : > "$JOB/queue"
    while IFS= read -r package; do
        [[ -n "$package" && "$package" != yq ]] || continue
        # Formula names only: never interpret config strings as options or code.
        if [[ ! "$package" =~ ^[A-Za-z0-9][A-Za-z0-9@+._/-]*$ || "$package" == *..* ]]; then
            echo "Invalid formula name: $package" >&2
            return 1
        fi
        grep -Fxq "$package" "$JOB/queue" || printf '%s\n' "$package" >> "$JOB/queue"
    done < "$JOB/candidates"
    : > "$JOB/completed"
    : > "$JOB/failures"
    : > "$JOB/current"
    : > "$JOB/worker.log"
    printf '0\n' > "$JOB/retries"
    checkpoint_installed || return 1
    if [[ "${2:-}" == --paused ]]; then
        touch "$JOB/pause-requested"
        set_status paused
    else
        set_status pending
    fi
    printf '%s\n' "$JOB" > "$STATE_ROOT/latest.tmp"
    mv "$STATE_ROOT/latest.tmp" "$STATE_ROOT/latest"
    register_agent || return 1
    if [[ "${2:-}" == --paused ]]; then
        echo "Package queue saved paused. Choose Resume in the window when you want compilation to begin."
    else
        echo "Package queue saved and registered to run now and resume at login."
    fi
    echo "One package at a time; build parallelism: $jobs."
    if [[ "$ALLOW_SOURCE_BUILDS" == 1 ]]; then
        echo "Explicit source-build fallback. Finished packages are retained; interrupted builds may restart the current formula."
    else
        echo "Package integrations, removals and Neovim providers finish later with option 2."
    fi
    show_status
}

start_queue() {
    local lock="$STATE_ROOT/create.lock" owner owner_command result
    mkdir -p "$STATE_ROOT" || return 1
    if ! mkdir "$lock" 2>/dev/null; then
        owner=$(cat "$lock/pid" 2>/dev/null || true)
        case "$owner" in
            ''|*[!0-9]*) echo "Queue creation is locked; inspect $lock before retrying." >&2; return 1 ;;
        esac
        owner_command=$(ps -p "$owner" -o command= 2>/dev/null || true)
        if [[ "$owner" != "$$" && "$owner_command" == *background-packages.sh*start* ]] && kill -0 "$owner" 2>/dev/null; then
            echo "Another queue is being prepared." >&2
            return 1
        fi
        rm -f "$lock/pid"
        rmdir "$lock" 2>/dev/null && mkdir "$lock" || return 1
    fi
    printf '%s\n' "$$" > "$lock/pid"
    prepare_queue "$@"
    result=$?
    rm -f "$lock/pid"
    rmdir "$lock" 2>/dev/null || true
    return "$result"
}

run_queue() {
    load_job || return 1
    case "$(cat "$JOB/status")" in packages_ready|paused|cancelled) return 0 ;; esac
    if ! mkdir "$JOB/lock" 2>/dev/null; then
        worker_alive && return 0
        rm -f "$JOB/lock/pid"
        rmdir "$JOB/lock" 2>/dev/null || return 1
        mkdir "$JOB/lock" 2>/dev/null || return 0
    fi
    printf '%s\n' "$$" > "$JOB/lock/pid"
    local brew package child_pid="" failed=0
    brew=$(cat "$JOB/brew")
    # On logout/termination leave a durable checkpoint. A reboot may bypass traps;
    # stale-lock detection handles that on the next login.
    interrupt_worker() {
        trap - TERM INT HUP
        if [[ -n "$child_pid" ]]; then
            kill -TERM "$child_pid" 2>/dev/null || true
            wait "$child_pid" 2>/dev/null || true
        fi
        set_status interrupted
        rm -f "$JOB/lock/pid"
        rmdir "$JOB/lock" 2>/dev/null || true
        exit 130
    }
    trap interrupt_worker TERM INT HUP
    export HOMEBREW_MAKE_JOBS="$(cat "$JOB/build-jobs")"
    export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1
    export HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_NO_INSTALL_UPGRADE=1
    export HOMEBREW_NO_ASK=1 HOMEBREW_NO_SUDO=1
    export NONINTERACTIVE=1
    unset SUDO_ASKPASS SUDOERS_FILE SUDOERS_SETUP_DONE HOMEBREW_GIT_PATH
    if [[ ! -x "$brew" ]]; then
        echo "Homebrew executable is missing: $brew" >&2
        set_status needs_attention
        rm -f "$JOB/lock/pid"; rmdir "$JOB/lock"
        return 1
    fi
    local brew_environment
    if ! brew_environment=$("$brew" shellenv); then
        set_status needs_attention
        rm -f "$JOB/lock/pid"; rmdir "$JOB/lock"
        return 1
    fi
    eval "$brew_environment"
    set_status running
    : > "$JOB/failures"
    while IFS= read -r package; do
        if [[ -f "$JOB/pause-requested" ]]; then
            set_status paused
            : > "$JOB/current"
            rm -f "$JOB/lock/pid"
            rmdir "$JOB/lock" 2>/dev/null || true
            trap - TERM INT HUP
            return 0
        fi
        # Reuse formulas from earlier foreground runs and other queues too.
        # Existing versions are sufficient here; this is not an upgrade job.
        if "$brew" list --versions "$package" >/dev/null 2>&1; then
            grep -Fxq "$package" "$JOB/completed" || printf '%s\n' "$package" >> "$JOB/completed"
            echo "Already installed; reusing: $package"
            continue
        fi
        if grep -Fxq "$package" "$JOB/completed"; then
            grep -Fxv "$package" "$JOB/completed" > "$JOB/completed.tmp" || true
            mv "$JOB/completed.tmp" "$JOB/completed"
        fi
        printf '%s\n' "$package" > "$JOB/current"
        date +%s > "$JOB/current-started-at"
        echo "$(date): Installing $package (build jobs: $HOMEBREW_MAKE_JOBS)"
        nice -n 10 "$brew" install "$package" </dev/null &
        child_pid=$!
        if wait "$child_pid" && "$brew" list --versions "$package" >/dev/null 2>&1; then
            grep -Fxq "$package" "$JOB/completed" || printf '%s\n' "$package" >> "$JOB/completed"
            echo "Completed: $package"
        else
            printf '%s\n' "$package" >> "$JOB/failures"
            echo "Failed: $package; attempting the next package." >&2
            failed=1
        fi
        child_pid=""
    done < "$JOB/queue"
    : > "$JOB/current"
    if [[ "$failed" == 0 ]]; then
        set_status packages_ready
        rm -f "$JOB/next-retry" "$JOB/pause-requested"
        echo "Packages are ready. Run the main installer, option 2, to finish environment configuration."
    else
        local retries delay
        retries=$(cat "$JOB/retries" 2>/dev/null || echo 0)
        retries=$((retries + 1))
        printf '%s\n' "$retries" > "$JOB/retries"
        delay=$((retries * 300))
        (( delay <= 1800 )) || delay=1800
        printf '%s\n' "$(( $(date +%s) + delay ))" > "$JOB/next-retry"
        set_status retry_wait
        echo "Some packages failed. Retrying unfinished packages in $delay seconds; inspect the log for the cause."
    fi
    rm -f "$JOB/lock/pid"
    rmdir "$JOB/lock" 2>/dev/null || true
    trap - TERM INT HUP
    return "$failed"
}

worker_loop() {
    load_job || return 1
    while true; do
        case "$(cat "$JOB/status")" in packages_ready|paused|cancelled|needs_attention) return 0 ;; esac
        if [[ -f "$JOB/pause-requested" ]]; then set_status paused; return 0; fi
        if [[ "$(cat "$JOB/status")" == retry_wait && -f "$JOB/next-retry" ]]; then
            if (( $(date +%s) < $(cat "$JOB/next-retry") )); then
                sleep 5
                continue
            fi
        fi
        run_queue
        case "$(cat "$JOB/status")" in retry_wait) ;; *) return 0 ;; esac
    done
}

case "${1:-status}" in
    status) show_status ;;
    busy) queue_busy ;;
    verify) shift; verify_queue "$@" ;;
    log) load_job && tail -f "$JOB/worker.log" ;;
    window)
        load_job || exit 1
        # Refresh only the presentation snapshot; never replace a running worker.
        if [[ -f "$SCRIPT_DIR/macos-package-status.js" ]] && ! cmp -s "$SCRIPT_DIR/macos-package-status.js" "$JOB/status-window.js"; then
            cp "$SCRIPT_DIR/macos-package-status.js" "$JOB/status-window.js.tmp" && mv "$JOB/status-window.js.tmp" "$JOB/status-window.js" || exit 1
        fi
        # UI commands can gain controls without replacing the executing worker.
        cp "$SCRIPT_DIR/background-packages.sh" "$JOB/controller.sh.tmp" && mv "$JOB/controller.sh.tmp" "$JOB/controller.sh" || exit 1
        printf 'yes\n' > "$JOB/show-window"
        register_window
        ;;
    start|resume|run|pause|stop|abandon|disable)
        [[ "$(uname -s)" == Darwin ]] || { echo "Background package setup is macOS only." >&2; exit 1; }
        [[ "$EUID" != 0 ]] || { echo "Run as the Mac login user, not root." >&2; exit 1; }
        if [[ "$(uname -m)" == x86_64 ]]; then
            case "$1" in
                start)
                    [[ "$ALLOW_SOURCE_BUILDS" == 1 ]] || { echo "Intel installs are binary-only. Use compile-macos-packages.py --allow-source-builds <formula> for last-resort compilation." >&2; exit 1; }
                    ;;
                resume|run)
                    load_job && [[ -f "$JOB/allow-source-builds" && "$(cat "$JOB/allow-source-builds")" == yes ]] || { echo "This queue has no explicit source-build approval. It will not run on Intel." >&2; exit 1; }
                    ;;
            esac
        fi
        case "$1" in
            start) shift; start_queue "$@" ;;
            run) worker_loop ;;
            stop)
                load_job || exit 1
                case "$(cat "$JOB/status")" in packages_ready|cancelled) echo "No unfinished package work to stop."; exit 0 ;; esac
                touch "$JOB/pause-requested"
                set_status stopping
                # Unload only this queue's worker service. launchd terminates
                # its process group, including the active compiler children.
                launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
                attempts=0
                while worker_alive && (( attempts < 30 )); do
                    sleep 0.2
                    attempts=$((attempts + 1))
                done
                if worker_alive; then
                    echo "Stop requested, but the worker has not exited yet. Check status before resuming." >&2
                    exit 1
                fi
                set_status paused
                echo "Queue stopped. Completed packages are retained. Option 3 or Resume continues unfinished work."
                ;;
            pause)
                load_job || exit 1
                case "$(cat "$JOB/status")" in packages_ready|cancelled) echo "No unfinished package work to pause."; exit 0 ;; esac
                touch "$JOB/pause-requested"
                if ! worker_alive; then
                    set_status paused
                    : > "$JOB/current"
                fi
                echo "Pause requested. The current package will finish before the queue pauses."
                ;;
            resume)
                load_job || exit 1
                if worker_alive; then
                    echo "The package queue is already running."
                    launchctl kickstart "$DOMAIN/$WINDOW_LABEL" 2>/dev/null || register_window
                    exit 0
                fi
                [[ "$(cat "$JOB/status")" != packages_ready ]] || { show_status; exit 0; }
                # Refresh code only while idle. Preserve queue/config/checkpoints.
                cp "$0" "$JOB/runner.sh.tmp" && mv "$JOB/runner.sh.tmp" "$JOB/runner.sh" || exit 1
                checkpoint_installed || exit 1
                rm -f "$JOB/pause-requested" "$JOB/next-retry"
                set_status pending
                register_agent preserve
                ;;
            abandon)
                load_job || exit 1
                if worker_alive; then echo "Cannot abandon a running queue." >&2; exit 1; fi
                set_status cancelled
                echo "Queue abandoned. Installed packages and logs have been retained."
                ;;
            disable)
                if load_job >/dev/null; then
                    if worker_alive; then echo "Pause the active queue and wait for its current formula before disabling it." >&2; exit 1; fi
                    set_status cancelled
                fi
                launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
                launchctl bootout "$DOMAIN/$WINDOW_LABEL" 2>/dev/null || true
                rm -f "$PLIST" "$WINDOW_PLIST"
                echo "Package LaunchAgents disabled. Installed packages, checkpoints and logs are retained."
                ;;
        esac
        ;;
    *) echo "Usage: bash background-packages.sh {start config.yaml|status|window|log|resume|pause|stop|abandon|disable}" >&2; exit 1 ;;
esac
