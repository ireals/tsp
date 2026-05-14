#!/system/bin/sh
# TEE Simulator Plus — Shell Bridge (Command Router)
# Entry point for WebUI commands via ksu.exec()

SCRIPT_DIR="${0%/*}"
MODDIR="${MODDIR:-${SCRIPT_DIR}/..}"

# Source logging library
LOG_COMPONENT="bridge"
. "$MODDIR/scripts/lib/logger.sh"

# Timeout in seconds for backend script execution
BRIDGE_TIMEOUT=30

# Whitelist of allowed commands
WHITELIST="keybox_add keybox_list keybox_select keybox_delete keybox_validate target_list_installed target_add target_remove target_import target_export profiler_run profiler_reference profiler_calibrate config_get config_set log_tail"

# --- Utility functions ---

# Extract a JSON string field value from input
_json_get_str() {
    echo "$1" | grep -o "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/"
}

# Output a JSON error response and exit
_respond_error() {
    _status_code="$1"
    _message="$2"
    echo "{\"status\": $_status_code, \"message\": \"$_message\"}"
    exit "$_status_code"
}

# Check if a command is in the whitelist
_is_whitelisted() {
    _cmd="$1"
    for _allowed in $WHITELIST; do
        if [ "$_cmd" = "$_allowed" ]; then
            return 0
        fi
    done
    return 1
}

# Resolve the backend script path based on command prefix
_resolve_backend() {
    _cmd="$1"
    case "$_cmd" in
        keybox_*)
            echo "$MODDIR/scripts/keybox_manager.sh"
            ;;
        target_*)
            echo "$MODDIR/scripts/target_manager.sh"
            ;;
        profiler_*)
            echo "$MODDIR/scripts/latency_profiler.sh"
            ;;
        config_*|log_*)
            echo "$MODDIR/scripts/config_manager.sh"
            ;;
        *)
            echo ""
            ;;
    esac
}

# --- Main execution ---

_main() {
    _input="$1"
    _start_time=$(date '+%s' 2>/dev/null || echo 0)

    # Validate input is provided
    if [ -z "$_input" ]; then
        log_error "No input provided"
        _respond_error 400 "No input provided"
    fi

    # Extract command from JSON input
    _command=$(_json_get_str "$_input" "command")

    if [ -z "$_command" ]; then
        log_error "No command field in input"
        _respond_error 400 "Missing command field"
    fi

    # Validate command against whitelist
    if ! _is_whitelisted "$_command"; then
        log_warn "Rejected unknown command: $_command"
        echo "{\"status\": 400, \"message\": \"Unknown command\"}"
        exit 0
    fi

    # Resolve backend script
    _backend=$(_resolve_backend "$_command")

    if [ -z "$_backend" ]; then
        log_error "No backend resolved for command: $_command"
        _respond_error 500 "Internal routing error"
    fi

    if [ ! -f "$_backend" ]; then
        log_error "Backend script not found: $_backend"
        _respond_error 500 "Backend script not found"
    fi

    log_info "Executing command: $_command -> $_backend"

    # Execute backend script with timeout
    # Run in background, capture output, enforce timeout
    _tmp_out="${MODDIR}/logs/.bridge_out_$$"
    _tmp_err="${MODDIR}/logs/.bridge_err_$$"

    # Launch backend in background, redirect stderr to temp file
    sh "$_backend" "$_input" >"$_tmp_out" 2>"$_tmp_err" &
    _bg_pid=$!

    # Wait with timeout
    _elapsed=0
    while [ $_elapsed -lt $BRIDGE_TIMEOUT ]; do
        # Check if process is still running
        if ! kill -0 "$_bg_pid" 2>/dev/null; then
            break
        fi
        sleep 1
        _elapsed=$((_elapsed + 1))
    done

    # Check if process is still running (timeout exceeded)
    if kill -0 "$_bg_pid" 2>/dev/null; then
        kill -9 "$_bg_pid" 2>/dev/null
        wait "$_bg_pid" 2>/dev/null

        _end_time=$(date '+%s' 2>/dev/null || echo 0)
        _duration=$((_end_time - _start_time))
        log_error "Command timed out after ${BRIDGE_TIMEOUT}s: $_command (duration=${_duration}s)"

        # Clean up temp files
        rm -f "$_tmp_out" "$_tmp_err" 2>/dev/null

        echo "{\"status\": 408, \"message\": \"Timeout\"}"
        exit 0
    fi

    # Process completed — get exit status
    wait "$_bg_pid" 2>/dev/null
    _exit_code=$?

    # Read output
    _output=""
    if [ -f "$_tmp_out" ]; then
        _output=$(cat "$_tmp_out" 2>/dev/null)
    fi

    # Read stderr for error details
    _stderr=""
    if [ -f "$_tmp_err" ]; then
        _stderr=$(cat "$_tmp_err" 2>/dev/null)
    fi

    # Clean up temp files
    rm -f "$_tmp_out" "$_tmp_err" 2>/dev/null

    # Calculate duration
    _end_time=$(date '+%s' 2>/dev/null || echo 0)
    _duration=$((_end_time - _start_time))

    # Handle execution errors
    if [ $_exit_code -ne 0 ] && [ -z "$_output" ]; then
        # Backend failed without producing output
        _err_msg=$(echo "$_stderr" | head -1 | sed 's/"/\\"/g')
        [ -z "$_err_msg" ] && _err_msg="Backend exited with code $_exit_code"

        log_error "Command failed: $_command (exit=$_exit_code, duration=${_duration}s) - $_err_msg"
        echo "{\"status\": 500, \"message\": \"$_err_msg\"}"
        exit 0
    fi

    # Validate output is non-empty
    if [ -z "$_output" ]; then
        log_error "Command produced no output: $_command (duration=${_duration}s)"
        echo "{\"status\": 500, \"message\": \"No response from backend\"}"
        exit 0
    fi

    # Log success
    log_info "Command completed: $_command (exit=$_exit_code, duration=${_duration}s)"

    # Log stderr as debug info if present (don't leak to stdout)
    if [ -n "$_stderr" ]; then
        log_debug "stderr from $_command: $_stderr"
    fi

    # Output the backend response (should already be valid JSON)
    echo "$_output"
    exit 0
}

# Trap to ensure cleanup on unexpected termination
trap 'rm -f "${MODDIR}/logs/.bridge_out_$$" "${MODDIR}/logs/.bridge_err_$$" 2>/dev/null' EXIT

# Run main — capture all stderr to prevent leaking to stdout
_main "$1" 2>/dev/null
