#!/system/bin/sh
# TEE Simulator Plus — Config & log manager

MODDIR="${MODDIR:-/data/adb/modules/tee-simulator-plus}"
CONFIG_FILE="$MODDIR/config/config.json"
LOG_FILE="$MODDIR/logs/module.log"

mkdir -p "$MODDIR/config" "$MODDIR/logs" 2>/dev/null

_json_get_str() {
    echo "$1" | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
}

_json_get_num() {
    echo "$1" | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\([0-9.]*\).*/\1/p" | head -1
}

_escape_json() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

_defaults() {
    cat <<'EOF'
{
  "schemaVersion": 1,
  "detectionThreshold": 1.1,
  "sampleCount": 500,
  "latencyEqualizerEnabled": true,
  "logLevel": "INFO",
  "referenceProfile": null
}
EOF
}

cmd_config_get() {
    if [ ! -f "$CONFIG_FILE" ]; then
        _defaults > "$CONFIG_FILE"
        chmod 0644 "$CONFIG_FILE"
    fi
    _content=$(cat "$CONFIG_FILE" 2>/dev/null)
    [ -z "$_content" ] && _content=$(_defaults)
    # Inline as data
    echo "{\"status\":0,\"data\":$_content}"
}

cmd_config_set() {
    _key=$(_json_get_str "$1" "key")
    _value=$(_json_get_str "$1" "value")
    [ -z "$_value" ] && _value=$(_json_get_num "$1" "value")

    [ -z "$_key" ] && { echo '{"status":1,"message":"key required"}'; return 1; }

    case "$_key" in
        detectionThreshold)
            _ok=$(awk "BEGIN{v=$_value+0; if(v>=1.01 && v<=2.0) print 1; else print 0}")
            [ "$_ok" != "1" ] && { echo '{"status":2,"message":"detectionThreshold must be 1.01-2.0"}'; return 2; }
            sed -i "s/\"detectionThreshold\"[[:space:]]*:[[:space:]]*[0-9.]*/\"detectionThreshold\": $_value/" "$CONFIG_FILE"
            ;;
        sampleCount)
            case "$_value" in *[!0-9]*) echo '{"status":2,"message":"sampleCount must be integer"}'; return 2 ;; esac
            [ "$_value" -lt 100 ] && { echo '{"status":2,"message":"sampleCount must be >=100"}'; return 2; }
            [ "$_value" -gt 5000 ] && { echo '{"status":2,"message":"sampleCount must be <=5000"}'; return 2; }
            sed -i "s/\"sampleCount\"[[:space:]]*:[[:space:]]*[0-9]*/\"sampleCount\": $_value/" "$CONFIG_FILE"
            ;;
        logLevel)
            case "$_value" in
                ERROR|WARN|INFO|DEBUG) ;;
                *) echo '{"status":2,"message":"logLevel must be ERROR|WARN|INFO|DEBUG"}'; return 2 ;;
            esac
            sed -i "s/\"logLevel\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"logLevel\": \"$_value\"/" "$CONFIG_FILE"
            ;;
        latencyEqualizerEnabled)
            case "$_value" in true|false) ;; *) echo '{"status":2,"message":"must be true|false"}'; return 2 ;; esac
            sed -i "s/\"latencyEqualizerEnabled\"[[:space:]]*:[[:space:]]*\(true\|false\)/\"latencyEqualizerEnabled\": $_value/" "$CONFIG_FILE"
            ;;
        *)
            echo "{\"status\":2,\"message\":\"Unknown key: $_key\"}"
            return 2
            ;;
    esac

    chmod 0644 "$CONFIG_FILE"
    _value_e=$(_escape_json "$_value")
    echo "{\"status\":0,\"data\":{\"key\":\"$_key\",\"value\":\"$_value_e\"}}"
}

cmd_log_tail() {
    _lines=$(_json_get_num "$1" "lines")
    [ -z "$_lines" ] && _lines=200

    if [ ! -f "$LOG_FILE" ]; then
        echo '{"status":0,"data":{"lines":""}}'
        return 0
    fi

    _content=$(tail -n "$_lines" "$LOG_FILE" 2>/dev/null)
    # Encode newlines as \n for JSON
    _encoded=$(printf '%s' "$_content" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk 'BEGIN{ORS=""} {if(NR>1) printf "\\n"; print}')
    echo "{\"status\":0,\"data\":{\"lines\":\"$_encoded\"}}"
}

# Dispatcher
_input="$1"
_command=$(_json_get_str "$_input" "command")

case "$_command" in
    config_get) cmd_config_get ;;
    config_set) cmd_config_set "$_input" ;;
    log_tail)   cmd_log_tail "$_input" ;;
    *) echo "{\"status\":1,\"message\":\"Unknown: $_command\"}" ;;
esac
