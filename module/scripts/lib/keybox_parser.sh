#!/system/bin/sh
# TEE Simulator Plus — Keybox XML parser/validator
# Minimal XML parsing using grep/sed for Android environment.

# Error codes
INVALID_KEYBOX_SCHEMA=10
INVALID_PEM_ENCODING=11

# Validate keybox XML structure for required elements
keybox_validate_structure() {
    _xml_file="$1"

    if [ ! -f "$_xml_file" ]; then
        echo "{\"valid\": false, \"error\": \"INVALID_KEYBOX_SCHEMA\", \"message\": \"File not found: $_xml_file\"}"
        return $INVALID_KEYBOX_SCHEMA
    fi

    # Check for AndroidAttestation root element
    if ! grep -q '<AndroidAttestation' "$_xml_file" 2>/dev/null; then
        echo "{\"valid\": false, \"error\": \"INVALID_KEYBOX_SCHEMA\", \"message\": \"Missing required element: AndroidAttestation\"}"
        return $INVALID_KEYBOX_SCHEMA
    fi

    # Check for Keybox element
    if ! grep -q '<Keybox' "$_xml_file" 2>/dev/null; then
        echo "{\"valid\": false, \"error\": \"INVALID_KEYBOX_SCHEMA\", \"message\": \"Missing required element: Keybox\"}"
        return $INVALID_KEYBOX_SCHEMA
    fi

    # Check for Key element with algorithm attribute
    if ! grep -q '<Key[[:space:]].*algorithm=' "$_xml_file" 2>/dev/null; then
        echo "{\"valid\": false, \"error\": \"INVALID_KEYBOX_SCHEMA\", \"message\": \"Missing required element: Key with algorithm attribute\"}"
        return $INVALID_KEYBOX_SCHEMA
    fi

    # Check for PrivateKey element
    if ! grep -q '<PrivateKey' "$_xml_file" 2>/dev/null; then
        echo "{\"valid\": false, \"error\": \"INVALID_KEYBOX_SCHEMA\", \"message\": \"Missing required element: PrivateKey\"}"
        return $INVALID_KEYBOX_SCHEMA
    fi

    # Check for CertificateChain element
    if ! grep -q '<CertificateChain' "$_xml_file" 2>/dev/null; then
        echo "{\"valid\": false, \"error\": \"INVALID_KEYBOX_SCHEMA\", \"message\": \"Missing required element: CertificateChain\"}"
        return $INVALID_KEYBOX_SCHEMA
    fi

    echo "{\"valid\": true}"
    return 0
}

# Validate PEM blocks within the keybox XML
keybox_validate_pem() {
    _xml_file="$1"

    if [ ! -f "$_xml_file" ]; then
        echo "{\"valid\": false, \"error\": \"INVALID_PEM_ENCODING\", \"message\": \"File not found: $_xml_file\"}"
        return $INVALID_PEM_ENCODING
    fi

    # Extract PEM blocks (content between BEGIN/END markers)
    _pem_count=0
    _invalid_count=0
    _in_pem=0
    _pem_content=""

    while IFS= read -r _line; do
        case "$_line" in
            *"-----BEGIN"*)
                _in_pem=1
                _pem_content=""
                ;;
            *"-----END"*)
                _in_pem=0
                _pem_count=$((_pem_count + 1))
                # Validate base64 content via openssl
                if [ -n "$_pem_content" ]; then
                    echo "$_pem_content" | openssl base64 -d > /dev/null 2>&1
                    if [ $? -ne 0 ]; then
                        _invalid_count=$((_invalid_count + 1))
                    fi
                else
                    _invalid_count=$((_invalid_count + 1))
                fi
                _pem_content=""
                ;;
            *)
                if [ $_in_pem -eq 1 ]; then
                    # Strip whitespace and accumulate base64 content
                    _cleaned=$(echo "$_line" | tr -d '[:space:]')
                    if [ -n "$_cleaned" ]; then
                        _pem_content="${_pem_content}${_cleaned}
"
                    fi
                fi
                ;;
        esac
    done < "$_xml_file"

    if [ $_pem_count -eq 0 ]; then
        echo "{\"valid\": false, \"error\": \"INVALID_PEM_ENCODING\", \"message\": \"No PEM blocks found\"}"
        return $INVALID_PEM_ENCODING
    fi

    if [ $_invalid_count -gt 0 ]; then
        echo "{\"valid\": false, \"error\": \"INVALID_PEM_ENCODING\", \"message\": \"$_invalid_count of $_pem_count PEM blocks have invalid encoding\"}"
        return $INVALID_PEM_ENCODING
    fi

    echo "{\"valid\": true, \"pemBlockCount\": $_pem_count}"
    return 0
}

# Extract metadata from keybox XML
keybox_extract_metadata() {
    _xml_file="$1"

    if [ ! -f "$_xml_file" ]; then
        echo "{\"error\": \"File not found: $_xml_file\"}"
        return 1
    fi

    # Extract algorithm from Key element's algorithm attribute
    _algorithm=$(grep '<Key[[:space:]]' "$_xml_file" 2>/dev/null | sed 's/.*algorithm="\([^"]*\)".*/\1/' | head -1)
    _algorithm="${_algorithm:-unknown}"

    # Extract first certificate PEM block for subject info
    _cert_subject=""
    _in_cert=0
    _cert_pem=""

    while IFS= read -r _line; do
        case "$_line" in
            *"-----BEGIN CERTIFICATE"*)
                _in_cert=1
                _cert_pem="-----BEGIN CERTIFICATE-----
"
                ;;
            *"-----END CERTIFICATE"*)
                if [ $_in_cert -eq 1 ]; then
                    _cert_pem="${_cert_pem}-----END CERTIFICATE-----
"
                    # Get subject from first certificate only
                    _cert_subject=$(echo "$_cert_pem" | openssl x509 -subject -noout 2>/dev/null | sed 's/^subject=//' | sed 's/^subject= //')
                    break
                fi
                ;;
            *)
                if [ $_in_cert -eq 1 ]; then
                    _cert_pem="${_cert_pem}${_line}
"
                fi
                ;;
        esac
    done < "$_xml_file"

    _cert_subject="${_cert_subject:-unknown}"

    # Escape quotes in subject for JSON
    _cert_subject_escaped=$(echo "$_cert_subject" | sed 's/"/\\"/g')

    echo "{\"algorithm\": \"$_algorithm\", \"certificateSubject\": \"$_cert_subject_escaped\"}"
    return 0
}

# Compute SHA-256 hash of keybox file
keybox_compute_hash() {
    _xml_file="$1"

    if [ ! -f "$_xml_file" ]; then
        echo "{\"error\": \"File not found: $_xml_file\"}"
        return 1
    fi

    _hash=$(sha256sum "$_xml_file" 2>/dev/null | awk '{print $1}')

    if [ -z "$_hash" ]; then
        echo "{\"error\": \"Failed to compute SHA-256 hash\"}"
        return 1
    fi

    echo "{\"hash\": \"$_hash\", \"algorithm\": \"SHA-256\"}"
    return 0
}

# Full validation: structure + PEM
keybox_validate() {
    _xml_file="$1"

    # Run structure validation
    _struct_result=$(keybox_validate_structure "$_xml_file")
    _struct_status=$?

    if [ $_struct_status -ne 0 ]; then
        echo "{\"valid\": false, \"structureValid\": false, \"pemValid\": false, \"details\": $_struct_result}"
        return $_struct_status
    fi

    # Run PEM validation
    _pem_result=$(keybox_validate_pem "$_xml_file")
    _pem_status=$?

    if [ $_pem_status -ne 0 ]; then
        echo "{\"valid\": false, \"structureValid\": true, \"pemValid\": false, \"details\": $_pem_result}"
        return $_pem_status
    fi

    echo "{\"valid\": true, \"structureValid\": true, \"pemValid\": true, \"details\": $_pem_result}"
    return 0
}
