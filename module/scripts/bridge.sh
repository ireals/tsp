#!/system/bin/sh
# TEE Simulator Plus — Shell Bridge (Command Router)
# Entry: sh bridge.sh '<json input>'

# Auto-detect MODDIR from where this script lives
SCRIPT_DIR="${0%/*}"
if [ -z "$MODDIR" ]; then
    case "$SCRIPT_DIR" in
        /*) MODDIR=$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd) ;;
        *)  MODDIR="" ;;
    esac
fi
# Fallback to known module IDs
if [ -z "$MODDIR" ] || [ ! -d "$MODDIR" ]; then
    for candidate in /data/adb/modules/tricky_store /data/adb/modules/tee-simulator-plus; do
        if [ -d "$candidate" ]; then
            MODDIR="$candidate"
            break
        fi
    done
fi
TRICKY_STORE_DIR="/data/adb/tricky_store"

# Whitelist
WHITELIST="status_get keybox_get keybox_upload keybox_remove target_list_installed target_add target_remove target_import target_export profiler_run profiler_reference profiler_calibrate config_get config_set log_tail equalizer_get equalizer_set"

# Extract a JSON string field
_json_get_str() {
    echo "$1" | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
}

_is_whitelisted() {
    for w in $WHITELIST; do
        [ "$1" = "$w" ] && return 0
    done
    return 1
}

_resolve_backend() {
    case "$1" in
        status_get|keybox_*) echo "$MODDIR/scripts/keybox_manager.sh" ;;
        target_*)            echo "$MODDIR/scripts/target_manager.sh" ;;
        profiler_*)          echo "$MODDIR/scripts/latency_profiler.sh" ;;
        equalizer_*)         echo "$MODDIR/scripts/equalizer_manager.sh" ;;
        config_*|log_*)      echo "$MODDIR/scripts/config_manager.sh" ;;
        *)                   echo "" ;;
    esac
}

_input="$1"

if [ -z "$_input" ]; then
    echo '{"status":400,"message":"No input"}'
    exit 0
fi

_command=$(_json_get_str "$_input" "command")

if [ -z "$_command" ]; then
    echo '{"status":400,"message":"Missing command field"}'
    exit 0
fi

if ! _is_whitelisted "$_command"; then
    echo '{"status":400,"message":"Unknown command: '"$_command"'"}'
    exit 0
fi

_backend=$(_resolve_backend "$_command")

if [ -z "$_backend" ] || [ ! -f "$_backend" ]; then
    echo '{"status":500,"message":"Backend not found"}'
    exit 0
fi

# Execute backend with the full input
export MODDIR
export TRICKY_STORE_DIR
_output=$(sh "$_backend" "$_input" 2>/dev/null)
_exit=$?

if [ -z "$_output" ]; then
    echo '{"status":500,"message":"No response from backend (exit='"$_exit"')"}'
    exit 0
fi

echo "$_output"
exit 0
