#!/system/bin/sh
# TEE Simulator Plus — Target package management script

SCRIPT_DIR="${0%/*}"
MODDIR="${MODDIR:-${SCRIPT_DIR}/..}"

. "$MODDIR/scripts/lib/logger.sh"

LOG_COMPONENT="target_manager"

CONFIG_FILE="$MODDIR/config/config.json"

# Extract a JSON string field from input
_json_get_str() {
    echo "$1" | grep -o "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/"
}

# Read targetList array from config as newline-separated list
_read_target_list() {
    if [ ! -f "$CONFIG_FILE" ]; then
        return 0
    fi
    # Extract targetList entries (package names between quotes in the array)
    awk '
        /"targetList"/ { in_array=1; next }
        in_array && /\]/ { exit }
        in_array { gsub(/[",[:space:]]/, ""); if (length > 0) print }
    ' "$CONFIG_FILE"
}

# Get count of items in targetList
_target_count() {
    _count=$(_read_target_list | wc -l | tr -d ' ')
    # Handle empty list
    if [ "$(_read_target_list)" = "" ]; then
        echo "0"
    else
        echo "$_count"
    fi
}

# Write targetList array back to config.json
_write_target_list() {
    _list="$1"

    if [ ! -f "$CONFIG_FILE" ]; then
        return 1
    fi

    # Build JSON array string from newline-separated list
    _json_array="["
    _first=1
    _IFS_BAK="$IFS"
    IFS='
'
    for _pkg in $_list; do
        [ -z "$_pkg" ] && continue
        if [ "$_first" = "1" ]; then
            _json_array="${_json_array}\"$_pkg\""
            _first=0
        else
            _json_array="${_json_array}, \"$_pkg\""
        fi
    done
    IFS="$_IFS_BAK"
    _json_array="${_json_array}]"

    # Replace targetList in config using sed
    # Handle multiline array by collapsing to single line first
    _tmp_config="${CONFIG_FILE}.tmp"
    awk -v new_list="$_json_array" '
        /"targetList"[[:space:]]*:/ {
            # Print the new targetList line
            printf "  \"targetList\": %s,\n", new_list
            # Skip old array content
            if ($0 ~ /\]/) next
            in_array=1
            next
        }
        in_array {
            if ($0 ~ /\]/) { in_array=0 }
            next
        }
        { print }
    ' "$CONFIG_FILE" > "$_tmp_config"

    if [ -s "$_tmp_config" ]; then
        mv -f "$_tmp_config" "$CONFIG_FILE"
        chmod 0600 "$CONFIG_FILE" 2>/dev/null
    else
        rm -f "$_tmp_config" 2>/dev/null
        return 1
    fi

    return 0
}

# Validate package name format (RFC 1035 style, case insensitive)
_validate_package_name() {
    _pkg="$1"
    # Must match: starts with letter, segments separated by dots, each segment starts with letter
    echo "$_pkg" | grep -qiE '^[a-z][a-z0-9]*(\.[a-z][a-z0-9]*)+$'
    return $?
}

# List installed third-party packages with target status
cmd_target_list_installed() {
    _target_list=$(_read_target_list)

    # Get third-party packages
    _packages=$(pm list packages -3 2>/dev/null | sed 's/^package://')

    if [ -z "$_packages" ]; then
        echo "{\"status\": 0, \"data\": []}"
        return 0
    fi

    _result="["
    _first=1
    _IFS_BAK="$IFS"
    IFS='
'
    for _pkg in $_packages; do
        [ -z "$_pkg" ] && continue

        # Get app label (best effort)
        _app_name=""
        _app_info=$(dumpsys package "$_pkg" 2>/dev/null | grep -i "applicationInfo" | head -1)
        if [ -n "$_app_info" ]; then
            _app_name=$(echo "$_app_info" | sed 's/.*label=\([^ ]*\).*/\1/' | tr -d '\r')
        fi
        _app_name="${_app_name:-$_pkg}"

        # Check if package is in target list
        _is_target="false"
        echo "$_target_list" | grep -qx "$_pkg" && _is_target="true"

        if [ "$_first" = "1" ]; then
            _result="${_result}{\"packageName\": \"$_pkg\", \"appName\": \"$_app_name\", \"isTarget\": $_is_target}"
            _first=0
        else
            _result="${_result}, {\"packageName\": \"$_pkg\", \"appName\": \"$_app_name\", \"isTarget\": $_is_target}"
        fi
    done
    IFS="$_IFS_BAK"

    _result="${_result}]"
    echo "{\"status\": 0, \"data\": $_result}"
    return 0
}

# Add a package to the target list
cmd_target_add() {
    _pkg=$(_json_get_str "$1" "packageName")

    if [ -z "$_pkg" ]; then
        echo "{\"status\": 1, \"message\": \"Missing required parameter: packageName\"}"
        return 1
    fi

    # Step 1: Validate package name format
    if ! _validate_package_name "$_pkg"; then
        log_error "Invalid package name format: $_pkg"
        echo "{\"status\": 2, \"message\": \"Invalid package name format: must match RFC 1035 (e.g., com.example.app)\"}"
        return 2
    fi

    # Step 2: Check for duplicates
    _target_list=$(_read_target_list)
    if echo "$_target_list" | grep -qx "$_pkg"; then
        log_warn "Package already in target list: $_pkg"
        echo "{\"status\": 3, \"message\": \"Package already in target list: $_pkg\"}"
        return 3
    fi

    # Step 3: Add to targetList
    if [ -n "$_target_list" ]; then
        _new_list="${_target_list}
${_pkg}"
    else
        _new_list="$_pkg"
    fi

    _write_target_list "$_new_list"
    _new_count=$(_target_count)

    log_info "Target added: $_pkg (total: $_new_count)"
    echo "{\"status\": 0, \"data\": {\"packageName\": \"$_pkg\", \"count\": $_new_count}}"
    return 0
}

# Remove a package from the target list
cmd_target_remove() {
    _pkg=$(_json_get_str "$1" "packageName")

    if [ -z "$_pkg" ]; then
        echo "{\"status\": 1, \"message\": \"Missing required parameter: packageName\"}"
        return 1
    fi

    _target_list=$(_read_target_list)

    # Check if package exists in list
    if ! echo "$_target_list" | grep -qx "$_pkg"; then
        log_warn "Package not in target list: $_pkg"
        echo "{\"status\": 2, \"message\": \"Package not in target list: $_pkg\"}"
        return 2
    fi

    # Remove the package
    _new_list=$(echo "$_target_list" | grep -vx "$_pkg")

    _write_target_list "$_new_list"
    _new_count=$(_target_count)

    log_info "Target removed: $_pkg (total: $_new_count)"
    echo "{\"status\": 0, \"data\": {\"packageName\": \"$_pkg\", \"count\": $_new_count}}"
    return 0
}

# Import targets from a text file
cmd_target_import() {
    _path=$(_json_get_str "$1" "path")

    if [ -z "$_path" ]; then
        echo "{\"status\": 1, \"message\": \"Missing required parameter: path\"}"
        return 1
    fi

    if [ ! -f "$_path" ]; then
        log_error "Import file not found: $_path"
        echo "{\"status\": 2, \"message\": \"File not found: $_path\"}"
        return 2
    fi

    _target_list=$(_read_target_list)
    _imported=0
    _duplicates=0

    # Read file, skip comments and empty lines
    while IFS= read -r _line || [ -n "$_line" ]; do
        # Trim whitespace
        _line=$(echo "$_line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        # Skip empty lines and comments
        [ -z "$_line" ] && continue
        case "$_line" in
            \#*) continue ;;
        esac

        # Validate format
        if ! _validate_package_name "$_line"; then
            continue
        fi

        # Check for duplicate
        if echo "$_target_list" | grep -qx "$_line"; then
            _duplicates=$((_duplicates + 1))
            continue
        fi

        # Add to list
        if [ -n "$_target_list" ]; then
            _target_list="${_target_list}
${_line}"
        else
            _target_list="$_line"
        fi
        _imported=$((_imported + 1))
    done < "$_path"

    # Write updated list
    _write_target_list "$_target_list"
    _total=$(_target_count)

    log_info "Targets imported: $_imported new, $_duplicates duplicates, $_total total"
    echo "{\"status\": 0, \"data\": {\"imported\": $_imported, \"duplicates\": $_duplicates, \"total\": $_total}}"
    return 0
}

# Export target list to a text file
cmd_target_export() {
    _export_path="$MODDIR/target.txt"
    _target_list=$(_read_target_list)

    # Write header and packages
    {
        echo "# Tricky-Addon compatible target list"
        echo "# Generated by TEE Simulator Plus"
        echo ""
        if [ -n "$_target_list" ]; then
            echo "$_target_list"
        fi
    } > "$_export_path"

    _count=$(_target_count)

    log_info "Targets exported to: $_export_path (count: $_count)"
    echo "{\"status\": 0, \"data\": {\"path\": \"$_export_path\", \"count\": $_count}}"
    return 0
}

# Main dispatcher
_main() {
    _input="$1"

    if [ -z "$_input" ]; then
        echo "{\"status\": 1, \"message\": \"No input provided\"}"
        return 1
    fi

    _command=$(_json_get_str "$_input" "command")

    if [ -z "$_command" ]; then
        echo "{\"status\": 1, \"message\": \"No command specified\"}"
        return 1
    fi

    log_debug "Dispatching command: $_command"

    case "$_command" in
        target_list_installed)
            cmd_target_list_installed
            ;;
        target_add)
            cmd_target_add "$_input"
            ;;
        target_remove)
            cmd_target_remove "$_input"
            ;;
        target_import)
            cmd_target_import "$_input"
            ;;
        target_export)
            cmd_target_export "$_input"
            ;;
        *)
            echo "{\"status\": 1, \"message\": \"Unknown command: $_command\"}"
            return 1
            ;;
    esac
}

# Run main dispatcher if executed directly (not sourced)
case "$0" in
    *target_manager.sh)
        _main "$1"
        ;;
esac
