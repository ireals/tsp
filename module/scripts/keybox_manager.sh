#!/system/bin/sh
# TEE Simulator Plus — Keybox manager (Tricky-Store compatible)
# Single keybox.xml at /data/adb/tricky_store/keybox.xml

MODDIR="${MODDIR:-/data/adb/modules/tee-simulator-plus}"
TRICKY_STORE_DIR="${TRICKY_STORE_DIR:-/data/adb/tricky_store}"
CONFIG_FILE="$MODDIR/config/config.json"
KEYBOX_FILE="$TRICKY_STORE_DIR/keybox.xml"
META_FILE="$TRICKY_STORE_DIR/keybox.meta"

mkdir -p "$TRICKY_STORE_DIR" 2>/dev/null

_json_get_str() {
    echo "$1" | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
}

_escape_json() {
    # Escape backslash, quote, newline for JSON
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' '
}

_validate_keybox() {
    _file="$1"
    [ -f "$_file" ] || { echo "MISSING_FILE"; return 1; }
    grep -q '<AndroidAttestation' "$_file" 2>/dev/null || { echo "INVALID_KEYBOX_SCHEMA: AndroidAttestation"; return 1; }
    grep -q '<Keybox' "$_file" 2>/dev/null || { echo "INVALID_KEYBOX_SCHEMA: Keybox"; return 1; }
    grep -q '<Key[[:space:]].*algorithm=' "$_file" 2>/dev/null || { echo "INVALID_KEYBOX_SCHEMA: Key"; return 1; }
    grep -q '<PrivateKey' "$_file" 2>/dev/null || { echo "INVALID_KEYBOX_SCHEMA: PrivateKey"; return 1; }
    grep -q '<CertificateChain' "$_file" 2>/dev/null || { echo "INVALID_KEYBOX_SCHEMA: CertificateChain"; return 1; }
    echo "OK"
    return 0
}

_extract_algorithm() {
    grep '<Key[[:space:]]' "$1" 2>/dev/null | sed 's/.*algorithm="\([^"]*\)".*/\1/' | head -1
}

_extract_subject() {
    # Extract first cert's PEM and get subject via openssl
    awk '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/' "$1" 2>/dev/null \
        | sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' \
        | head -100 \
        | openssl x509 -subject -noout 2>/dev/null \
        | sed 's/^subject= *//; s/^subject=//'
}

cmd_status_get() {
    if [ -f "$KEYBOX_FILE" ]; then
        _present=true
        _name=$(cat "$META_FILE" 2>/dev/null | sed -n 's/^displayName=//p')
        _name=${_name:-keybox.xml}
    else
        _present=false
        _name=""
    fi
    _target_count=0
    if [ -f "$TRICKY_STORE_DIR/target.txt" ]; then
        _target_count=$(grep -v '^[[:space:]]*#' "$TRICKY_STORE_DIR/target.txt" 2>/dev/null | grep -v '^[[:space:]]*$' | wc -l | tr -d ' ')
    fi
    _name_esc=$(_escape_json "$_name")
    echo "{\"status\":0,\"data\":{\"keyboxPresent\":$_present,\"keyboxName\":\"$_name_esc\",\"targetCount\":$_target_count}}"
}

cmd_keybox_get() {
    if [ ! -f "$KEYBOX_FILE" ]; then
        echo '{"status":0,"data":{"present":false}}'
        return 0
    fi
    _algo=$(_extract_algorithm "$KEYBOX_FILE")
    _algo=${_algo:-unknown}
    _subj=$(_extract_subject "$KEYBOX_FILE")
    _subj=${_subj:-unknown}
    _hash=$(sha256sum "$KEYBOX_FILE" 2>/dev/null | awk '{print $1}')
    _hash=${_hash:-unknown}
    _name=$(cat "$META_FILE" 2>/dev/null | sed -n 's/^displayName=//p')
    _name=${_name:-keybox.xml}

    _algo_e=$(_escape_json "$_algo")
    _subj_e=$(_escape_json "$_subj")
    _name_e=$(_escape_json "$_name")
    _path_e=$(_escape_json "$KEYBOX_FILE")

    echo "{\"status\":0,\"data\":{\"present\":true,\"displayName\":\"$_name_e\",\"algorithm\":\"$_algo_e\",\"certificateSubject\":\"$_subj_e\",\"hash\":\"$_hash\",\"path\":\"$_path_e\"}}"
}

cmd_keybox_upload() {
    _path=$(_json_get_str "$1" "path")
    _name=$(_json_get_str "$1" "displayName")
    [ -z "$_name" ] && _name="keybox.xml"

    if [ -z "$_path" ]; then
        echo '{"status":1,"message":"path is required"}'
        return 1
    fi

    if [ ! -f "$_path" ]; then
        echo '{"status":2,"message":"Source file not found"}'
        return 2
    fi

    _val=$(_validate_keybox "$_path")
    if [ "$_val" != "OK" ]; then
        _val_e=$(_escape_json "$_val")
        echo "{\"status\":3,\"message\":\"$_val_e\"}"
        return 3
    fi

    mkdir -p "$TRICKY_STORE_DIR"
    cp -f "$_path" "$KEYBOX_FILE"
    chmod 0644 "$KEYBOX_FILE"

    # Save metadata
    {
        echo "displayName=$_name"
        echo "addedAt=$(date '+%s' 2>/dev/null || echo 0)"
    } > "$META_FILE"
    chmod 0644 "$META_FILE"

    _name_e=$(_escape_json "$_name")
    _path_e=$(_escape_json "$KEYBOX_FILE")
    echo "{\"status\":0,\"data\":{\"displayName\":\"$_name_e\",\"path\":\"$_path_e\"}}"
}

cmd_keybox_remove() {
    rm -f "$KEYBOX_FILE" "$META_FILE" 2>/dev/null
    echo '{"status":0,"data":{"removed":true}}'
}

# Main dispatcher
_input="$1"
_command=$(_json_get_str "$_input" "command")

case "$_command" in
    status_get)     cmd_status_get ;;
    keybox_get)     cmd_keybox_get ;;
    keybox_upload)  cmd_keybox_upload "$_input" ;;
    keybox_remove)  cmd_keybox_remove ;;
    *)              echo "{\"status\":1,\"message\":\"Unknown: $_command\"}" ;;
esac
