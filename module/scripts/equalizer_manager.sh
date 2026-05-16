#!/system/bin/sh
# TEE Simulator Plus — Latency Equalizer config manager

TRICKY_STORE_DIR="${TRICKY_STORE_DIR:-/data/adb/tricky_store}"
EQ_CONFIG="$TRICKY_STORE_DIR/equalizer.conf"

mkdir -p "$TRICKY_STORE_DIR" 2>/dev/null

_json_get_str() {
    echo "$1" | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
}

_json_get_num() {
    echo "$1" | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\([0-9.]*\).*/\1/p" | head -1
}

_json_get_bool() {
    _v=$(echo "$1" | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p" | head -1)
    [ -z "$_v" ] && _v=$(_json_get_str "$1" "$2")
    echo "$_v"
}

cmd_equalizer_get() {
    if [ ! -f "$EQ_CONFIG" ]; then
        echo '{"status":0,"data":{"enabled":false,"targetMs":0,"stddevMs":0,"maxWaitMs":50}}'
        return 0
    fi
    _enabled=$(grep '^enabled=' "$EQ_CONFIG" | cut -d= -f2 | tr -d ' ')
    # Support both old "referenceMs" and new "targetMs"
    _target=$(grep '^targetMs=' "$EQ_CONFIG" | cut -d= -f2 | tr -d ' ')
    [ -z "$_target" ] && _target=$(grep '^referenceMs=' "$EQ_CONFIG" | cut -d= -f2 | tr -d ' ')
    _std=$(grep '^stddevMs=' "$EQ_CONFIG" | cut -d= -f2 | tr -d ' ')
    _max=$(grep '^maxWaitMs=' "$EQ_CONFIG" | cut -d= -f2 | tr -d ' ')
    _enabled=${_enabled:-false}
    _target=${_target:-0}
    _std=${_std:-0}
    _max=${_max:-50}
    echo "{\"status\":0,\"data\":{\"enabled\":$_enabled,\"targetMs\":$_target,\"stddevMs\":$_std,\"maxWaitMs\":$_max}}"
}

cmd_equalizer_set() {
    _enabled=$(_json_get_bool "$1" "enabled")
    _target=$(_json_get_num "$1" "targetMs")
    _std=$(_json_get_num "$1" "stddevMs")
    _max=$(_json_get_num "$1" "maxWaitMs")

    [ -z "$_enabled" ] && _enabled="false"
    [ -z "$_target" ] && _target="0"
    [ -z "$_std" ] && _std="0"
    [ -z "$_max" ] && _max="50"

    {
        echo "# TEE Simulator Plus — Latency Equalizer config"
        echo "# Read by patched AttestationPatcher in TEESimulator daemon"
        echo "# Goal: match HW Keystore attestation timing"
        echo "enabled=$_enabled"
        echo "targetMs=$_target"
        echo "stddevMs=$_std"
        echo "maxWaitMs=$_max"
    } > "$EQ_CONFIG"
    chmod 0644 "$EQ_CONFIG"

    echo "{\"status\":0,\"data\":{\"enabled\":$_enabled,\"targetMs\":$_target,\"stddevMs\":$_std,\"maxWaitMs\":$_max}}"
}

# Dispatcher
_input="$1"
_command=$(_json_get_str "$_input" "command")

case "$_command" in
    equalizer_get) cmd_equalizer_get ;;
    equalizer_set) cmd_equalizer_set "$_input" ;;
    *) echo "{\"status\":1,\"message\":\"Unknown: $_command\"}" ;;
esac
