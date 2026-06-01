#!/usr/bin/env bash
# lib/utils.sh — Utility helpers for File Backup Sync

# ---------------------------------------------------------------------------
# check_deps <cmd1> [cmd2 ...]
#   Verifies that all required commands are available on PATH.
# ---------------------------------------------------------------------------
check_deps() {
    local missing=0
    for cmd in "$@"; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "Required command not found: ${cmd}"
            missing=1
        fi
    done
    return "$missing"
}

# ---------------------------------------------------------------------------
# acquire_lock
#   Creates a lock file containing the current PID.
#   Exits with an error if another instance is already running.
# ---------------------------------------------------------------------------
acquire_lock() {
    local lock_file="${LOCK_FILE:-/tmp/file_backup_sync.lock}"

    if [[ -e "$lock_file" ]]; then
        local existing_pid
        existing_pid=$(cat "$lock_file" 2>/dev/null)
        if kill -0 "$existing_pid" 2>/dev/null; then
            log_error "Another sync is already running (PID ${existing_pid}). Aborting."
            exit 1
        else
            log_warn "Stale lock file found (PID ${existing_pid} is gone). Removing."
            rm -f "$lock_file"
        fi
    fi

    echo $$ > "$lock_file"
    log_debug "Lock acquired: ${lock_file} (PID $$)"
}

# ---------------------------------------------------------------------------
# release_lock
#   Removes the lock file. Called automatically via a trap.
# ---------------------------------------------------------------------------
release_lock() {
    local lock_file="${LOCK_FILE:-/tmp/file_backup_sync.lock}"
    rm -f "$lock_file"
    log_debug "Lock released: ${lock_file}"
}

# ---------------------------------------------------------------------------
# validate_sources <dir1> [dir2 ...]
#   Checks that each source directory exists and is readable.
# ---------------------------------------------------------------------------
validate_sources() {
    local ok=0
    for src in "$@"; do
        if [[ ! -d "$src" ]]; then
            log_error "Source directory does not exist: ${src}"
            ok=1
        elif [[ ! -r "$src" ]]; then
            log_error "Source directory is not readable: ${src}"
            ok=1
        fi
    done
    return "$ok"
}

# ---------------------------------------------------------------------------
# human_size <bytes>
#   Prints a human-readable size string (KB / MB / GB).
# ---------------------------------------------------------------------------
human_size() {
    local bytes=$1
    if   (( bytes < 1024 ));          then echo "${bytes} B"
    elif (( bytes < 1048576 ));        then printf "%.1f KB" "$(echo "scale=1; $bytes/1024"      | bc)"
    elif (( bytes < 1073741824 ));     then printf "%.1f MB" "$(echo "scale=1; $bytes/1048576"   | bc)"
    else                                    printf "%.1f GB" "$(echo "scale=1; $bytes/1073741824" | bc)"
    fi
}

# ---------------------------------------------------------------------------
# send_notification <status> <message>
#   Sends a desktop and/or email notification if enabled in config.
# ---------------------------------------------------------------------------
function send_notification() {
    local status="$1"
    local message="$2"

    if [[ "${NOTIFY_DESKTOP:-false}" == "true" ]]; then
        if command -v notify-send &>/dev/null; then
            notify-send "File Backup Sync [${status}]" "$message"
        fi
    fi

    if [[ "${NOTIFY_EMAIL:-false}" == "true" ]]; then
        if command -v mail &>/dev/null; then
            echo "$message" | mail \
                -s "${NOTIFY_EMAIL_SUBJECT:-[Backup] Sync report}" \
                -r "${NOTIFY_EMAIL_FROM:-backup@localhost}" \
                "${NOTIFY_EMAIL_TO:-root}"
        else
            log_warn "Email notification requested but 'mail' is not installed."
        fi
    fi
}

# ---------------------------------------------------------------------------
# gets the user input for a custom config config file
# ---------------------------------------------------------------------------
function get_user_input() {
    local temp_config="${SCRIPT_DIR:-.}/config/temp_config.conf"
    read -p "Enter Source Directories (space-separated): " src_input
    read -p "Enter Destination Directory: " dest_input
    read -p "Enter Destination Type (rsync/rclone): " dest_type_input

    touch "$temp_config"
    {
        echo "SOURCE_DIRS=\"$src_input\""
        echo "DEST_TYPE='$dest_type_input'"
        if [[ "$dest_type_input" == "rsync" ]]; then
            echo "RSYNC_DEST='$dest_input'"
        elif [[ "$dest_type_input" == "rclone" ]]; then
            echo "RCLONE_DEST='$dest_input'"
        fi
    } > "$temp_config"

    log_info "Temporary config file created at ${temp_config}"
    
}
