#!/system/bin/sh
# TEE Simulator Plus — Shared logging library
# Source this file from other scripts to use logging functions.

# Auto-detect MODDIR from script location or use default
if [ -z "$MODDIR" ]; then
    _logger_dir="${0%/*}"
    if [ -d "$_logger_dir/../../logs" ]; then
        MODDIR="$(cd "$_logger_dir/../.." 2>/dev/null && pwd)"
    else
        MODDIR="/data/adb/modules/tee-simulator-plus"
    fi
fi

LOG_FILE="$MODDIR/logs/module.log"
LOG_MAX_SIZE=5242880
LOG_COMPONENT="${LOG_COMPONENT:-unknown}"

# Log level constants: ERROR=0, WARN=1, INFO=2, DEBUG=3
LOG_LEVEL=2

# Convert level name to numeric value
_log_level_to_num() {
    case "$1" in
        ERROR) echo 0 ;;
        WARN)  echo 1 ;;
        INFO)  echo 2 ;;
        DEBUG) echo 3 ;;
        *)     echo 2 ;;
    esac
}

# Check if a message at the given level should be output
_log_should_output() {
    _level_num=$(_log_level_to_num "$1")
    [ "$_level_num" -le "$LOG_LEVEL" ]
}

# Rotate log file if it exceeds LOG_MAX_SIZE
_log_rotate() {
    if [ -f "$LOG_FILE" ]; then
        _size=$(wc -c < "$LOG_FILE" 2>/dev/null | tr -d ' ')
        if [ "${_size:-0}" -gt "$LOG_MAX_SIZE" ]; then
            mv -f "$LOG_FILE" "${LOG_FILE}.1"
            : > "$LOG_FILE"
        fi
    fi
}

# Write a formatted log entry to LOG_FILE
_log_write() {
    _level="$1"
    _message="$2"

    _log_should_output "$_level" || return 0

    _timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "0000-00-00 00:00:00")
    _entry="$_timestamp [$_level] $LOG_COMPONENT: $_message"

    _log_dir="${LOG_FILE%/*}"
    [ -d "$_log_dir" ] || mkdir -p "$_log_dir" 2>/dev/null

    echo "$_entry" >> "$LOG_FILE" 2>/dev/null
    _write_status=$?

    _log_rotate

    return $_write_status
}

# Fallback: write to logcat
_log_fallback() {
    _level="$1"
    _message="$2"

    case "$_level" in
        ERROR) _priority="e" ;;
        WARN)  _priority="w" ;;
        INFO)  _priority="i" ;;
        DEBUG) _priority="d" ;;
        *)     _priority="i" ;;
    esac

    log -t TEESimulatorPlus -p "$_priority" "$LOG_COMPONENT: $_message" 2>/dev/null
}

# Public logging functions
log_error() {
    _log_write "ERROR" "$1" || _log_fallback "ERROR" "$1"
}

log_warn() {
    _log_write "WARN" "$1"
}

log_info() {
    _log_write "INFO" "$1"
}

log_debug() {
    _log_write "DEBUG" "$1"
}

# Initialize logging: read config, set level, ensure log directory
log_init() {
    _config_file="$MODDIR/config/config.json"
    _log_level_str="INFO"

    if [ -f "$_config_file" ]; then
        _extracted=$(grep '"logLevel"' "$_config_file" 2>/dev/null | sed 's/.*"logLevel"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        if [ -n "$_extracted" ]; then
            _log_level_str="$_extracted"
        fi
    fi

    LOG_LEVEL=$(_log_level_to_num "$_log_level_str")

    _log_dir="${LOG_FILE%/*}"
    [ -d "$_log_dir" ] || mkdir -p "$_log_dir" 2>/dev/null

    return 0
}

# Auto-initialize on source: load log level from config
log_init
