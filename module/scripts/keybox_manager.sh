#!/system/bin/sh
# TEE Simulator Plus — Keybox management script

SCRIPT_DIR="${0%/*}"
MODDIR="${MODDIR:-${SCRIPT_DIR}/..}"

. "$MODDIR/scripts/lib/logger.sh"
. "$MODDIR/scripts/lib/keybox_parser.sh"

LOG_COMPONENT="keybox_manager"

KEYBOX_DIR="$MODDIR/keyboxes"
CONFIG_FILE="$MODDIR/config/config.json"

# Extract a JSON string field from input
_json_get_str() {
    echo "$1" | grep -o "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/"
}

# Read a JSON field value (string or non-string) from config
_config_read_field() {
    _field="$1"
    if [ -f "$CONFIG_FILE" ]; then
        grep "\"$_field\"" "$CONFIG_FILE" 2>/dev/null | sed "s/.*\"$_field\"[[:space:]]*:[[:space:]]*\"\{0,1\}\([^,\"}]*\)\"\{0,1\}.*/\1/" | tr -d ' '
    fi
}

# Validate a keybox file
cmd_keybox_validate() {
    _path=$(_json_get_str "$1" "path")

    if [ -z "$_path" ]; then
        echo "{\"status\": 1, \"message\": \"Missing required parameter: path\"}"
        return 1
    fi

    _result=$(keybox_validate "$_path")
    _status=$?

    if [ $_status -eq 0 ]; then
        echo "{\"status\": 0, \"data\": $_result}"
    else
        echo "{\"status\": $_status, \"message\": \"Keybox validation failed\", \"data\": $_result}"
    fi
    return $_status
}

# Add a keybox to the managed collection
cmd_keybox_add() {
    _path=$(_json_get_str "$1" "path")
    _display_name=$(_json_get_str "$1" "displayName")

    if [ -z "$_path" ]; then
        echo "{\"status\": 1, \"message\": \"Missing required parameter: path\"}"
        return 1
    fi

    if [ -z "$_display_name" ]; then
        _display_name="Keybox $(date '+%Y%m%d%H%M%S')"
    fi

    # Step 1: Validate keybox
    _val_result=$(keybox_validate "$_path")
    _val_status=$?
    if [ $_val_status -ne 0 ]; then
        log_error "Keybox validation failed for: $_path"
        echo "{\"status\": 2, \"message\": \"Keybox validation failed\", \"data\": $_val_result}"
        return 2
    fi

    # Step 2: Compute SHA-256 hash
    _hash=$(sha256sum "$_path" 2>/dev/null | awk '{print $1}')
    if [ -z "$_hash" ]; then
        log_error "Failed to compute hash for: $_path"
        echo "{\"status\": 3, \"message\": \"Failed to compute SHA-256 hash\"}"
        return 3
    fi

    # Step 3: Check for duplicate
    if [ -f "$KEYBOX_DIR/${_hash}.xml" ]; then
        log_warn "Duplicate keybox detected: $_hash"
        echo "{\"status\": 4, \"message\": \"Duplicate keybox: a keybox with the same hash already exists\", \"data\": {\"id\": \"$_hash\"}}"
        return 4
    fi

    # Step 4: Copy to keyboxes/<hash>.xml
    mkdir -p "$KEYBOX_DIR" 2>/dev/null
    cp -f "$_path" "$KEYBOX_DIR/${_hash}.xml"
    chmod 0600 "$KEYBOX_DIR/${_hash}.xml"

    # Step 5: Extract metadata
    _metadata=$(keybox_extract_metadata "$KEYBOX_DIR/${_hash}.xml")
    _algorithm=$(echo "$_metadata" | grep -o '"algorithm"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"algorithm"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    _cert_subject=$(echo "$_metadata" | grep -o '"certificateSubject"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"certificateSubject"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    _algorithm="${_algorithm:-unknown}"
    _cert_subject="${_cert_subject:-unknown}"

    # Step 6: Add metadata entry to config.json keyboxMetadata array
    _added_at=$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')
    _new_entry="{\"id\": \"$_hash\", \"displayName\": \"$_display_name\", \"algorithm\": \"$_algorithm\", \"certificateSubject\": \"$_cert_subject\", \"addedAt\": \"$_added_at\"}"

    # Insert into keyboxMetadata array in config.json
    if [ -f "$CONFIG_FILE" ]; then
        # Check if keyboxMetadata is empty array
        if grep -q '"keyboxMetadata"[[:space:]]*:[[:space:]]*\[\]' "$CONFIG_FILE" 2>/dev/null; then
            sed -i "s/\"keyboxMetadata\"[[:space:]]*:[[:space:]]*\[\]/\"keyboxMetadata\": [$_new_entry]/" "$CONFIG_FILE"
        else
            # Append to existing array: replace last ] in keyboxMetadata with , newEntry]
            sed -i "/\"keyboxMetadata\"/,/\]/{
                s/\]$/, $_new_entry]/
            }" "$CONFIG_FILE"
        fi
    fi

    log_info "Keybox added: id=$_hash displayName=$_display_name"

    # Step 7: Return success
    echo "{\"status\": 0, \"data\": {\"id\": \"$_hash\", \"displayName\": \"$_display_name\", \"addedAt\": \"$_added_at\"}}"
    return 0
}

# List all managed keyboxes with active flag
cmd_keybox_list() {
    _active_id=$(_config_read_field "activeKeyboxId")

    # Read keyboxMetadata from config
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "{\"status\": 0, \"data\": []}"
        return 0
    fi

    # Extract keyboxMetadata array content using awk
    _metadata_json=$(awk '
        BEGIN { in_array=0; depth=0; content="" }
        /"keyboxMetadata"/ { in_array=1; next }
        in_array && /\[/ { depth++; if(depth==1) next }
        in_array && /\]/ { depth--; if(depth==0) { print content; exit } }
        in_array && depth>=1 { content = content $0 "\n" }
    ' "$CONFIG_FILE")

    if [ -z "$_metadata_json" ]; then
        echo "{\"status\": 0, \"data\": []}"
        return 0
    fi

    # Build output array with isActive flag
    _output="["
    _first=1

    echo "$_metadata_json" | grep '"id"' | while IFS= read -r _line; do true; done

    # Parse entries by splitting on }, {
    _entries=$(echo "$_metadata_json" | tr '\n' ' ' | sed 's/},{/}\n{/g')

    echo "$_entries" | while IFS= read -r _entry; do
        [ -z "$_entry" ] && continue
        _entry_id=$(echo "$_entry" | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        [ -z "$_entry_id" ] && continue

        if [ "$_entry_id" = "$_active_id" ]; then
            _is_active="true"
        else
            _is_active="false"
        fi

        # Clean entry and add isActive
        _clean_entry=$(echo "$_entry" | sed 's/[{}]//g' | tr -d '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        if [ $_first -eq 1 ]; then
            _output="${_output}{${_clean_entry}, \"isActive\": $_is_active}"
            _first=0
        else
            _output="${_output}, {${_clean_entry}, \"isActive\": $_is_active}"
        fi
    done

    # Since the while loop runs in a subshell, rebuild output here
    _result="["
    _first=1
    _IFS_BAK="$IFS"
    IFS='
'
    for _entry in $(echo "$_entries"); do
        [ -z "$_entry" ] && continue
        _entry_id=$(echo "$_entry" | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        [ -z "$_entry_id" ] && continue

        if [ "$_entry_id" = "$_active_id" ]; then
            _is_active="true"
        else
            _is_active="false"
        fi

        _clean_entry=$(echo "$_entry" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/^{//;s/}$//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        if [ "$_first" = "1" ]; then
            _result="${_result}{${_clean_entry}, \"isActive\": $_is_active}"
            _first=0
        else
            _result="${_result}, {${_clean_entry}, \"isActive\": $_is_active}"
        fi
    done
    IFS="$_IFS_BAK"

    _result="${_result}]"
    echo "{\"status\": 0, \"data\": $_result}"
    return 0
}

# Select a keybox as active
cmd_keybox_select() {
    _id=$(_json_get_str "$1" "id")

    if [ -z "$_id" ]; then
        echo "{\"status\": 1, \"message\": \"Missing required parameter: id\"}"
        return 1
    fi

    # Step 1: Verify keybox file exists
    if [ ! -f "$KEYBOX_DIR/${_id}.xml" ]; then
        log_error "Keybox not found: $_id"
        echo "{\"status\": 2, \"message\": \"Keybox not found: $_id\"}"
        return 2
    fi

    # Step 2: Update activeKeyboxId in config.json
    if [ -f "$CONFIG_FILE" ]; then
        sed -i "s/\"activeKeyboxId\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"activeKeyboxId\": \"$_id\"/" "$CONFIG_FILE"
    fi

    log_info "Active keybox set to: $_id"
    echo "{\"status\": 0, \"data\": {\"activeKeyboxId\": \"$_id\"}}"
    return 0
}

# Delete a keybox
cmd_keybox_delete() {
    _id=$(_json_get_str "$1" "id")

    if [ -z "$_id" ]; then
        echo "{\"status\": 1, \"message\": \"Missing required parameter: id\"}"
        return 1
    fi

    # Step 1: Remove keybox file
    if [ -f "$KEYBOX_DIR/${_id}.xml" ]; then
        rm -f "$KEYBOX_DIR/${_id}.xml"
    else
        log_warn "Keybox file not found for deletion: $_id"
    fi

    # Step 2: Remove metadata entry from config.json
    if [ -f "$CONFIG_FILE" ]; then
        # Remove the entry matching this id from keyboxMetadata array
        # Use awk to rebuild the array without the matching entry
        _tmp_config="${CONFIG_FILE}.tmp"
        awk -v id="$_id" '
        BEGIN { in_array=0; skip_entry=0; first_entry=1; buffer="" }
        /"keyboxMetadata"[[:space:]]*:/ {
            in_array=1
            print
            next
        }
        in_array && /\[/ && !started {
            started=1
            printf "    ["
            next
        }
        in_array && started && /\]/ {
            print ""
            print "    ]" (match($0, /,$/) ? "," : "")
            in_array=0
            started=0
            next
        }
        in_array && started {
            if ($0 ~ "\"id\"[[:space:]]*:[[:space:]]*\"" id "\"") {
                skip_entry=1
            }
            if (!skip_entry) {
                buffer = buffer $0 "\n"
            }
            if ($0 ~ /\}/) {
                if (!skip_entry) {
                    # will print later
                } else {
                    skip_entry=0
                }
                if (!skip_entry) {
                    # entry complete
                }
            }
            next
        }
        { print }
        ' "$CONFIG_FILE" > "$_tmp_config" 2>/dev/null

        # Simpler approach: use sed to remove the entry
        # Remove entry containing the id from keyboxMetadata
        # This handles single-line entries
        sed -i "/{.*\"id\"[[:space:]]*:[[:space:]]*\"$_id\"/d" "$CONFIG_FILE"

        # Clean up trailing commas and empty arrays
        sed -i 's/,[[:space:]]*\]/]/' "$CONFIG_FILE"
        sed -i 's/\[[[:space:]]*,/[/' "$CONFIG_FILE"

        rm -f "$_tmp_config" 2>/dev/null
    fi

    # Step 3: If this was the active keybox, clear activeKeyboxId
    _active_id=$(_config_read_field "activeKeyboxId")
    if [ "$_active_id" = "$_id" ]; then
        sed -i "s/\"activeKeyboxId\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"activeKeyboxId\": \"\"/" "$CONFIG_FILE"
        log_info "Cleared active keybox (deleted keybox was active)"
    fi

    log_info "Keybox deleted: $_id"
    echo "{\"status\": 0, \"data\": {\"deletedId\": \"$_id\"}}"
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
        keybox_validate)
            cmd_keybox_validate "$_input"
            ;;
        keybox_add)
            cmd_keybox_add "$_input"
            ;;
        keybox_list)
            cmd_keybox_list
            ;;
        keybox_select)
            cmd_keybox_select "$_input"
            ;;
        keybox_delete)
            cmd_keybox_delete "$_input"
            ;;
        *)
            echo "{\"status\": 1, \"message\": \"Unknown command: $_command\"}"
            return 1
            ;;
    esac
}

# Run main dispatcher if executed directly (not sourced)
case "$0" in
    *keybox_manager.sh)
        _main "$1"
        ;;
esac
