#!/system/bin/sh
# TEE Simulator Plus — Latency Equalizer config manager
# Writes /data/adb/tricky_store/equalizer.conf which is read by the patched
# KeystoreInterceptor.kt at runtime.

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
        echo '{"status":0,"data":{"enabled":false,"referenceMs":0,"stddevMs":0,"detectionThreshold":1.1}}'
        return 0
    fi
    _enabled=$(grep '^enabled=' "$EQ_CONFIG" | cut -d= -f2 | tr -d ' ')
    _ref=$(grep '^referenceMs=' "$EQ_CONFIG" | cut -d= -f2 | tr -d ' ')
    _std=$(grep '^stddevMs=' "$EQ_CONFIG" | cut -d= -f2 | tr -d ' ')
    _th=$(grep '^detectionThreshold=' "$EQ_CONFIG" | cut -d= -f2 | tr -d ' ')
    _enabled=${_enabled:-false}
    _ref=${_ref:-0}
    _std=${_std:-0}
    _th=${_th:-1.1}
    echo "{\"status\":0,\"data\":{\"enabled\":$_enabled,\"referenceMs\":$_ref,\"stddevMs\":$_std,\"detectionThreshold\":$_th}}"
}

cmd_equalizer_set() {
    _enabled=$(_json_get_bool "$1" "enabled")
    _ref=$(_json_get_num "$1" "referenceMs")
    _std=$(_json_get_num "$1" "stddevMs")
    _th=$(_json_get_num "$1" "detectionThreshold")

    [ -z "$_enabled" ] && _enabled="false"
    [ -z "$_ref" ] && _ref="0"
    [ -z "$_std" ] && _std="0"
    [ -z "$_th" ] && _th="1.1"

    {
        echo "# TEE Simulator Plus — Latency Equalizer config"
        echo "# Read by patched KeystoreInterceptor in TrickyStore daemon"
        echo "enabled=$_enabled"
        echo "referenceMs=$_ref"
        echo "stddevMs=$_std"
        echo "detectionThreshold=$_th"
    } > "$EQ_CONFIG"
    chmod 0644 "$EQ_CONFIG"

    echo "{\"status\":0,\"data\":{\"enabled\":$_enabled,\"referenceMs\":$_ref,\"stddevMs\":$_std,\"detectionThreshold\":$_th}}"
}

# Dispatcher
_input="$1"
_command=$(_json_get_str "$_input" "command")

case "$_command" in
    equalizer_get) cmd_equalizer_get ;;
    equalizer_set) cmd_equalizer_set "$_input" ;;
    *) echo "{\"status\":1,\"message\":\"Unknown: $_command\"}" ;;
esac
