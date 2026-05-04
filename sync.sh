#!/usr/bin/env bash
# sync.sh — File Backup & Sync — Main Entry Point
#
# Usage:
#   ./sync.sh [OPTIONS]
#
# Options:
#   -c, --config <file>   Path to config file (default: config/config.conf)
#   -n, --dry-run         Show what would be transferred without making changes
#   -v, --verbose         Increase output verbosity (sets LOG_LEVEL=DEBUG)
#   -h, --help            Show this help message
#
# Examples:
#   ./sync.sh                          # Normal sync with default config
#   ./sync.sh --dry-run                # Preview changes only
#   ./sync.sh -c /etc/mybackup.conf    # Use a custom config file
# ---------------------------------------------------------------------------

set -euo pipefail
IFS=$'\n\t'

# ---------------------------------------------------------------------------
# Resolve script directory so relative paths always work regardless of where
# the script is called from.
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Source libraries (order matters: logger first, then utils)
# ---------------------------------------------------------------------------
# shellcheck source=lib/logger.sh
source "${SCRIPT_DIR}/lib/logger.sh"
# shellcheck source=lib/utils.sh
source "${SCRIPT_DIR}/lib/utils.sh"

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
CONFIG_FILE="${SCRIPT_DIR}/config/config.conf"
DRY_RUN=false

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
usage() {
    grep '^#' "$0" | grep -v '^#!/' | sed 's/^# \{0,1\}//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--config)  CONFIG_FILE="$2"; shift 2 ;;
        -n|--dry-run) DRY_RUN=true;     shift   ;;
        -v|--verbose) LOG_LEVEL="DEBUG"; shift   ;;
        -h|--help)    usage ;;
        *) log_error "Unknown option: $1"; usage ;;
    esac
done

# ---------------------------------------------------------------------------
# Load configuration
# ---------------------------------------------------------------------------
if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "Config file not found: ${CONFIG_FILE}"
    exit 1
fi

# Allow a local override file (git-ignored) to shadow the default config.
LOCAL_CONFIG="${CONFIG_FILE%.conf}.local.conf"
# shellcheck source=config/config.conf
source "$CONFIG_FILE"
if [[ -f "$LOCAL_CONFIG" ]]; then
    log_debug "Loading local config override: ${LOCAL_CONFIG}"
    # shellcheck source=/dev/null
    source "$LOCAL_CONFIG"
fi

# Re-evaluate LOG_DIR / LOG_FILE after config is loaded.
# LOG_DIR defaults to <script-dir>/logs if not set in the config file.
LOG_DIR="${LOG_DIR:-${SCRIPT_DIR}/logs}"
LOG_FILE="${LOG_DIR}/sync_$(date +%Y%m).log"
mkdir -p "$LOG_DIR"

# ---------------------------------------------------------------------------
# Trap: always release the lock and log completion on exit
# ---------------------------------------------------------------------------
_start_time=$(date +%s)

cleanup() {
    local exit_code=$?
    local end_time elapsed
    end_time=$(date +%s)
    elapsed=$(( end_time - _start_time ))

    if (( exit_code == 0 )); then
        log_info "Sync completed successfully in ${elapsed}s."
        send_notification "SUCCESS" "Sync completed in ${elapsed}s."
    else
        log_error "Sync failed (exit code ${exit_code}) after ${elapsed}s."
        send_notification "FAILURE" "Sync failed (exit code ${exit_code}) after ${elapsed}s."
    fi

    release_lock
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
log_info "=== File Backup & Sync starting ==="
log_info "Config : ${CONFIG_FILE}"
log_info "Log    : ${LOG_FILE}"
[[ "$DRY_RUN" == "true" ]] && log_warn "DRY-RUN mode — no files will be modified."

# Check required tools
case "${DEST_TYPE:-rsync}" in
    rsync)  check_deps rsync  || exit 1 ;;
    rclone) check_deps rclone || exit 1 ;;
    *)
        log_error "Unknown DEST_TYPE '${DEST_TYPE}'. Must be 'rsync' or 'rclone'."
        exit 1
        ;;
esac

# Validate source directories
# shellcheck disable=SC2086
validate_sources $SOURCE_DIRS || exit 1

# Acquire lock to prevent concurrent runs
acquire_lock

# ---------------------------------------------------------------------------
# Sync functions
# ---------------------------------------------------------------------------
sync_rsync() {
    local src="$1"
    local dest="${RSYNC_DEST}"
    local base_opts=(-a --delete --progress --human-readable)
    local extra_opts=()

    [[ "$DRY_RUN"        == "true" ]] && base_opts+=(--dry-run)
    [[ -n "${RSYNC_EXTRA_OPTS:-}" ]]  && IFS=' ' read -r -a extra_opts <<< "$RSYNC_EXTRA_OPTS"

    log_info "rsync: ${src} → ${dest}"
    rsync "${base_opts[@]}" "${extra_opts[@]}" "${src}/" "${dest}/$(basename "$src")/" \
        2>&1 | while IFS= read -r line; do log_debug "  $line"; done
}

sync_rclone() {
    local src="$1"
    local dest="${RCLONE_DEST}/$(basename "$src")"
    local base_opts=(sync --progress)
    local extra_opts=()

    [[ "$DRY_RUN"         == "true" ]] && base_opts+=(--dry-run)
    [[ -n "${RCLONE_EXTRA_OPTS:-}" ]]  && IFS=' ' read -r -a extra_opts <<< "$RCLONE_EXTRA_OPTS"

    log_info "rclone: ${src} → ${dest}"
    rclone "${base_opts[@]}" "${extra_opts[@]}" "$src" "$dest" \
        2>&1 | while IFS= read -r line; do log_debug "  $line"; done
}

# ---------------------------------------------------------------------------
# Main sync loop
# ---------------------------------------------------------------------------
for dir in $SOURCE_DIRS; do
    log_info "Processing: ${dir}"
    case "${DEST_TYPE}" in
        rsync)  sync_rsync  "$dir" ;;
        rclone) sync_rclone "$dir" ;;
    esac
done

# ---------------------------------------------------------------------------
# Post-sync: rotate old logs
# ---------------------------------------------------------------------------
rotate_logs
