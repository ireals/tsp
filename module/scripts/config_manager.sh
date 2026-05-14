#!/system/bin/sh
# TEE Simulator Plus — Configuration management script

SCRIPT_DIR="${0%/*}"
MODDIR="${MODDIR:-${SCRIPT_DIR}/..}"

. "$MODDIR/scripts/lib/logger.sh"

LOG_COMPONENT="config_manager"

CONFIG_FILE="$MODDIR/config/config.json"
SCHEMA_VERSION=1

# Output default configuration JSON
_config_defaults() {
    cat <<'DEFAULTS'
{
  "schemaVersion": 1,
  "activeKeyboxId": "",
  "targetList": [],
  "detectionThreshold": 1.1,
  "sampleCount": 500,
  "latencyEqualizerEnabled": true,
  "logLevel": "INFO",
  "referenceProfile": null,
  "keyboxMetadata": []
}
DEFAULTS
}

# Read and output full config.json content
config_get() {
    if [ -f "$CONFIG_FILE" ]; then
        cat "$CONFIG_FILE"
    else
        log_warn "Config file not found, returning defaults"
        _config_defaults
    fi
}

# Validate and set a config key/value pair
config_set() {
    _key="$1"
    _value="$2"

    # Validate key and value
    case "$_key" in
        detectionThreshold)
            # Must be a number between 1.01 and 2.0
            _valid=$(echo "$_value" | grep -E '^[0-9]+\.?[0-9]*$')
            if [ -z "$_valid" ]; then
                log_error "Invalid detectionThreshold value: $_value (must be number 1.01-2.0)"
                echo "{\"status\": 1, \"message\": \"Invalid detectionThreshold: must be a number between 1.01 and 2.0\"}"
                return 1
            fi
            # Check range using awk
            _in_range=$(awk "BEGIN { v=$_value; if (v >= 1.01 && v <= 2.0) print 1; else print 0 }")
            if [ "$_in_range" != "1" ]; then
                log_error "detectionThreshold out of range: $_value (must be 1.01-2.0)"
                echo "{\"status\": 1, \"message\": \"Invalid detectionThreshold: must be between 1.01 and 2.0\"}"
                return 1
            fi
            ;;
        sampleCount)
            # Must be an integer between 100 and 5000
            _valid=$(echo "$_value" | grep -E '^[0-9]+$')
            if [ -z "$_valid" ]; then
                log_error "Invalid sampleCount value: $_value (must be integer 100-5000)"
                echo "{\"status\": 1, \"message\": \"Invalid sampleCount: must be an integer between 100 and 5000\"}"
                return 1
            fi
            if [ "$_value" -lt 100 ] || [ "$_value" -gt 5000 ]; then
                log_error "sampleCount out of range: $_value (must be 100-5000)"
                echo "{\"status\": 1, \"message\": \"Invalid sampleCount: must be between 100 and 5000\"}"
                return 1
            fi
            ;;
        logLevel)
            # Must be ERROR, WARN, INFO, or DEBUG
            case "$_value" in
                ERROR|WARN|INFO|DEBUG) ;;
                *)
                    log_error "Invalid logLevel: $_value"
                    echo "{\"status\": 1, \"message\": \"Invalid logLevel: must be ERROR, WARN, INFO, or DEBUG\"}"
                    return 1
                    ;;
            esac
            ;;
        latencyEqualizerEnabled)
            # Must be true or false
            case "$_value" in
                true|false) ;;
                *)
                    log_error "Invalid latencyEqualizerEnabled: $_value"
                    echo "{\"status\": 1, \"message\": \"Invalid latencyEqualizerEnabled: must be true or false\"}"
                    return 1
                    ;;
            esac
            ;;
        *)
            log_error "Unknown config key: $_key"
            echo "{\"status\": 1, \"message\": \"Unknown config key: $_key\"}"
            return 1
            ;;
    esac

    # Ensure config file exists
    if [ ! -f "$CONFIG_FILE" ]; then
        _config_defaults > "$CONFIG_FILE"
    fi

    # Determine if value needs quotes (strings get quotes, numbers/booleans don't)
    case "$_key" in
        logLevel)
            sed -i "s/\"$_key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"$_key\": \"$_value\"/" "$CONFIG_FILE"
            ;;
        latencyEqualizerEnabled)
            sed -i "s/\"$_key\"[[:space:]]*:[[:space:]]*[a-z]*/\"$_key\": $_value/" "$CONFIG_FILE"
            ;;
        detectionThreshold|sampleCount)
            sed -i "s/\"$_key\"[[:space:]]*:[[:space:]]*[0-9.]*/\"$_key\": $_value/" "$CONFIG_FILE"
            ;;
    esac

    # Set restrictive permissions
    chmod 0600 "$CONFIG_FILE" 2>/dev/null

    log_info "Config updated: $_key=$_value"
    echo "{\"status\": 0, \"data\": {\"key\": \"$_key\", \"value\": \"$_value\"}}"
    return 0
}

# Migrate config schema if needed
config_migrate() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log_info "No config file found, creating defaults"
        _config_defaults > "$CONFIG_FILE"
        chmod 0600 "$CONFIG_FILE" 2>/dev/null
        echo "{\"status\": 0, \"data\": {\"migrated\": false, \"reason\": \"created_defaults\"}}"
        return 0
    fi

    _current_version=$(grep '"schemaVersion"' "$CONFIG_FILE" 2>/dev/null | sed 's/.*"schemaVersion"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/')
    _current_version="${_current_version:-0}"

    if [ "$_current_version" -eq "$SCHEMA_VERSION" ]; then
        log_debug "Config schema is current (version $SCHEMA_VERSION)"
        echo "{\"status\": 0, \"data\": {\"migrated\": false, \"reason\": \"already_current\"}}"
        return 0
    fi

    # Backup existing config
    cp -f "$CONFIG_FILE" "${CONFIG_FILE}.bak"
    log_info "Config backed up to ${CONFIG_FILE}.bak"

    # Apply migration (currently only version 1 exists)
    # Future migrations would go here as version checks
    _config_defaults > "$CONFIG_FILE"
    chmod 0600 "$CONFIG_FILE" 2>/dev/null

    log_info "Config migrated from version $_current_version to $SCHEMA_VERSION"
    echo "{\"status\": 0, \"data\": {\"migrated\": true, \"from\": $_current_version, \"to\": $SCHEMA_VERSION}}"
    return 0
}

# Output last N lines of module.log
log_tail() {
    _lines="${1:-200}"
    _log_file="$MODDIR/logs/module.log"

    if [ ! -f "$_log_file" ]; then
        echo "{\"status\": 1, \"message\": \"Log file not found\"}"
        return 1
    fi

    _content=$(tail -n "$_lines" "$_log_file" 2>/dev/null)
    # Escape for JSON output
    _escaped=$(echo "$_content" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "%s\\n", $0}' | sed 's/\\n$//')
    echo "{\"status\": 0, \"data\": {\"lines\": \"$_escaped\"}}"
    return 0
}

# Main dispatcher: parse command from input JSON
_main() {
    _input="$1"

    if [ -z "$_input" ]; then
        echo "{\"status\": 1, \"message\": \"No input provided\"}"
        return 1
    fi

    # Extract command from JSON input
    _command=$(echo "$_input" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

    if [ -z "$_command" ]; then
        echo "{\"status\": 1, \"message\": \"No command specified\"}"
        return 1
    fi

    case "$_command" in
        get)
            _data=$(config_get)
            echo "{\"status\": 0, \"data\": $_data}"
            ;;
        set)
            _key=$(echo "$_input" | grep -o '"key"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"key"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
            _value=$(echo "$_input" | grep -o '"value"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"value"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
            # Handle non-string values (numbers, booleans)
            if [ -z "$_value" ]; then
                _value=$(echo "$_input" | grep -o '"value"[[:space:]]*:[[:space:]]*[^,}]*' | sed 's/.*"value"[[:space:]]*:[[:space:]]*//' | tr -d ' ')
            fi
            config_set "$_key" "$_value"
            ;;
        migrate)
            config_migrate
            ;;
        log_tail)
            _lines=$(echo "$_input" | grep -o '"lines"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*"lines"[[:space:]]*:[[:space:]]*//')
            log_tail "${_lines:-200}"
            ;;
        *)
            echo "{\"status\": 1, \"message\": \"Unknown command: $_command\"}"
            return 1
            ;;
    esac
}

# Run main dispatcher if executed directly (not sourced)
case "$0" in
    *config_manager.sh)
        _main "$1"
        ;;
esac
