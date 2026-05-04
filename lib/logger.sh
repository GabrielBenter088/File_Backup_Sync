#!/usr/bin/env bash
# lib/logger.sh — Logging helper for File Backup Sync
# Usage: source this file, then call log_info / log_warn / log_error / log_debug

# Colours (disabled automatically when output is not a terminal)
if [[ -t 1 ]]; then
    _CLR_RESET="\033[0m"
    _CLR_DEBUG="\033[0;36m"   # cyan
    _CLR_INFO="\033[0;32m"    # green
    _CLR_WARN="\033[0;33m"    # yellow
    _CLR_ERROR="\033[0;31m"   # red
else
    _CLR_RESET="" _CLR_DEBUG="" _CLR_INFO="" _CLR_WARN="" _CLR_ERROR=""
fi

# Internal log level order
_level_order() {
    case "$1" in
        DEBUG) echo 0 ;;
        INFO)  echo 1 ;;
        WARN)  echo 2 ;;
        ERROR) echo 3 ;;
        *)     echo 1 ;;
    esac
}

_log() {
    local level="$1"; shift
    local message="$*"
    local configured_level="${LOG_LEVEL:-INFO}"

    # Skip if below configured log level
    if (( $(_level_order "$level") < $(_level_order "$configured_level") )); then
        return 0
    fi

    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local colour

    case "$level" in
        DEBUG) colour="$_CLR_DEBUG" ;;
        INFO)  colour="$_CLR_INFO"  ;;
        WARN)  colour="$_CLR_WARN"  ;;
        ERROR) colour="$_CLR_ERROR" ;;
        *)     colour=""            ;;
    esac

    local formatted="[${timestamp}] [${level}] ${message}"

    # Print to stdout with colour
    echo -e "${colour}${formatted}${_CLR_RESET}"

    # Append to log file (no colour codes)
    if [[ -n "${LOG_FILE:-}" ]]; then
        mkdir -p "$(dirname "$LOG_FILE")"
        echo "$formatted" >> "$LOG_FILE"
    fi
}

log_debug() { _log "DEBUG" "$@"; }
log_info()  { _log "INFO"  "$@"; }
log_warn()  { _log "WARN"  "$@"; }
log_error() { _log "ERROR" "$@"; }

# Rotate old log files, keeping LOG_RETENTION most-recent files.
rotate_logs() {
    local log_dir="${LOG_DIR:-./logs}"
    local retention="${LOG_RETENTION:-6}"
    local count
    count=$(find "$log_dir" -maxdepth 1 -name "sync_*.log" | wc -l)
    if (( count > retention )); then
        find "$log_dir" -maxdepth 1 -name "sync_*.log" \
            | sort | head -n $(( count - retention )) \
            | while IFS= read -r f; do rm -f "$f"; done
        log_info "Log rotation: removed $(( count - retention )) old log file(s)."
    fi
}
