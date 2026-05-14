#!/system/bin/sh
# TEE Simulator Plus — Latency profiler for timing side-channel detection

SCRIPT_DIR="${0%/*}"
MODDIR="${MODDIR:-${SCRIPT_DIR}/..}"

. "$MODDIR/scripts/lib/logger.sh"

LOG_COMPONENT="latency_profiler"

CONFIG_FILE="$MODDIR/config/config.json"

# Extract a JSON string field from input
_json_get_str() {
    echo "$1" | grep -o "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/"
}

# Extract a JSON numeric field from input
_json_get_num() {
    echo "$1" | grep -o "\"$2\"[[:space:]]*:[[:space:]]*[0-9.]*" | sed "s/.*\"$2\"[[:space:]]*:[[:space:]]*//"
}

# Read detection threshold from config
_read_threshold() {
    if [ -f "$CONFIG_FILE" ]; then
        _val=$(grep '"detectionThreshold"' "$CONFIG_FILE" 2>/dev/null | sed 's/.*"detectionThreshold"[[:space:]]*:[[:space:]]*\([0-9.]*\).*/\1/')
        echo "${_val:-1.1}"
    else
        echo "1.1"
    fi
}

# Get current time in nanoseconds (best effort)
_time_ns() {
    # Try nanosecond precision first
    _t=$(date '+%s%N' 2>/dev/null)
    if [ ${#_t} -gt 10 ]; then
        echo "$_t"
    else
        # Fallback: millisecond precision via /proc/uptime or seconds
        if [ -f /proc/uptime ]; then
            awk '{printf "%.0f\n", $1 * 1000000000}' /proc/uptime
        else
            echo "${_t}000000000"
        fi
    fi
}

# Perform a simulated attested keystore call
_call_attested() {
    # On a real device this would be: service call android.security.keystore2 1
    # Simulating with the actual binder call (will fail gracefully if not available)
    service call android.security.keystore2 1 > /dev/null 2>&1
}

# Perform a simulated non-attested keystore call
_call_non_attested() {
    # On a real device this would be a non-attestation keystore operation
    # Using a different transaction code for non-attestation path
    service call android.security.keystore2 2 > /dev/null 2>&1
}

# Sort numbers (one per line) in ascending order
_sort_numbers() {
    sort -n
}

# Calculate mean from sorted numbers (one per line)
_calc_mean() {
    awk '{ sum += $1; count++ } END { if (count > 0) printf "%.2f\n", sum/count; else print "0" }'
}

# Calculate standard deviation from numbers (one per line)
_calc_stddev() {
    awk '{ sum += $1; sumsq += $1*$1; count++ } END {
        if (count > 1) {
            mean = sum/count
            variance = (sumsq - sum*sum/count) / (count-1)
            if (variance < 0) variance = 0
            printf "%.2f\n", sqrt(variance)
        } else print "0"
    }'
}

# Remove outliers: top and bottom 5% from sorted data
_remove_outliers() {
    _total="$1"
    _trim=$(awk "BEGIN { t=int($_total * 0.05); if(t<1) t=1; print t }")
    _keep_start=$((_trim + 1))
    _keep_end=$((_total - _trim))
    if [ "$_keep_end" -lt "$_keep_start" ]; then
        _keep_end="$_keep_start"
    fi
    sed -n "${_keep_start},${_keep_end}p"
}

# Run the latency profiler
cmd_profiler_run() {
    _sample_count=$(_json_get_num "$1" "sampleCount")
    _cpu_core=$(_json_get_num "$1" "cpuCore")

    _sample_count="${_sample_count:-500}"
    _cpu_core="${_cpu_core:-0}"

    log_info "Profiler run: sampleCount=$_sample_count cpuCore=$_cpu_core"

    # Step 1: Pin to CPU core via taskset
    _pid=$$
    taskset -p "$(printf '%x' $((1 << _cpu_core)))" "$_pid" > /dev/null 2>&1

    # Step 2: Pre-warming: 50 dummy keystore calls
    _warmup=0
    while [ $_warmup -lt 50 ]; do
        _call_attested
        _warmup=$((_warmup + 1))
    done

    # Step 3: Measure attested path
    _attested_times=""
    _i=0
    while [ $_i -lt "$_sample_count" ]; do
        _start=$(_time_ns)
        _call_attested
        _end=$(_time_ns)
        _elapsed=$((_end - _start))
        _attested_times="${_attested_times}${_elapsed}
"
        _i=$((_i + 1))
    done

    # Step 4: Measure non-attested path
    _non_attested_times=""
    _i=0
    while [ $_i -lt "$_sample_count" ]; do
        _start=$(_time_ns)
        _call_non_attested
        _end=$(_time_ns)
        _elapsed=$((_end - _start))
        _non_attested_times="${_non_attested_times}${_elapsed}
"
        _i=$((_i + 1))
    done

    # Step 5: Remove outliers (sort, trim top/bottom 5%)
    _attested_sorted=$(echo "$_attested_times" | grep -v '^$' | _sort_numbers)
    _non_attested_sorted=$(echo "$_non_attested_times" | grep -v '^$' | _sort_numbers)

    _total_attested=$(echo "$_attested_sorted" | wc -l | tr -d ' ')
    _total_non_attested=$(echo "$_non_attested_sorted" | wc -l | tr -d ' ')

    _attested_trimmed=$(echo "$_attested_sorted" | _remove_outliers "$_total_attested")
    _non_attested_trimmed=$(echo "$_non_attested_sorted" | _remove_outliers "$_total_non_attested")

    _trimmed_attested_count=$(echo "$_attested_trimmed" | wc -l | tr -d ' ')
    _trimmed_non_attested_count=$(echo "$_non_attested_trimmed" | wc -l | tr -d ' ')

    # Step 6: Calculate statistics
    # Convert nanoseconds to milliseconds for reporting
    _t_a_ns=$(echo "$_attested_trimmed" | _calc_mean)
    _t_n_ns=$(echo "$_non_attested_trimmed" | _calc_mean)

    _t_a=$(awk "BEGIN { printf \"%.4f\", $_t_a_ns / 1000000 }")
    _t_n=$(awk "BEGIN { printf \"%.4f\", $_t_n_ns / 1000000 }")
    _diff=$(awk "BEGIN { printf \"%.4f\", ($_t_a_ns - $_t_n_ns) / 1000000 }")
    _ratio=$(awk "BEGIN { if ($_t_a_ns > 0) printf \"%.4f\", $_t_n_ns / $_t_a_ns; else print \"0\" }")

    # Step 7: Filtered bad samples count
    _filtered_attested=$((_total_attested - _trimmed_attested_count))
    _filtered_non_attested=$((_total_non_attested - _trimmed_non_attested_count))
    _filtered_total=$((_filtered_attested + _filtered_non_attested))
    _total_samples=$((_total_attested + _total_non_attested))

    # Step 8: Judge result
    _threshold=$(_read_threshold)
    _judgment=$(awk "BEGIN { if ($_ratio > $_threshold) print \"Negative\"; else print \"Positive\" }")
    # Note: ratio = T_n / T_a. If T_n/T_a > threshold, non-attested is slower (unexpected) = Negative
    # If T_n/T_a <= threshold, attested is proportionally slower = Positive (TEE detected)
    # Re-evaluate: ratio < 1 means attested is slower. We compare ratio against threshold differently.
    # The spec says: if ratio > threshold then "Positive" else "Negative"
    _judgment=$(awk "BEGIN { if ($_ratio > $_threshold) print \"Positive\"; else print \"Negative\" }")

    # Step 9: Log result
    log_info "Register timer bound_cpu${_cpu_core} attested ${_t_a}ms non-attested ${_t_n}ms diff ${_diff}ms ratio ${_ratio}x filteredBadSamples=${_filtered_total}/${_total_samples} threshold > ${_threshold}x ${_judgment}"

    # Step 10: Return metrics as JSON
    echo "{\"status\": 0, \"data\": {\"cpuCore\": $_cpu_core, \"sampleCount\": $_sample_count, \"attestedMeanMs\": $_t_a, \"nonAttestedMeanMs\": $_t_n, \"diffMs\": $_diff, \"ratio\": $_ratio, \"filteredBadSamples\": $_filtered_total, \"totalSamples\": $_total_samples, \"threshold\": $_threshold, \"judgment\": \"$_judgment\"}}"
    return 0
}

# Return stored reference profile from config
cmd_profiler_reference() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "{\"status\": 1, \"message\": \"Config file not found\"}"
        return 1
    fi

    # Extract referenceProfile from config
    _ref=$(awk '
        /"referenceProfile"/ {
            if ($0 ~ /null/) { print "null"; exit }
            in_obj=1
            content=$0
            if ($0 ~ /\}/) { print content; exit }
            next
        }
        in_obj {
            content = content $0
            if ($0 ~ /\}/) { print content; exit }
        }
    ' "$CONFIG_FILE")

    if [ -z "$_ref" ] || [ "$_ref" = "null" ]; then
        echo "{\"status\": 0, \"data\": null}"
    else
        echo "{\"status\": 0, \"data\": $_ref}"
    fi
    return 0
}

# Calibrate: measure hardware-backed timing and save reference profile
cmd_profiler_calibrate() {
    _sample_count=$(_json_get_num "$1" "sampleCount")
    _sample_count="${_sample_count:-500}"

    log_info "Profiler calibrate: sampleCount=$_sample_count"

    # Pre-warming
    _warmup=0
    while [ $_warmup -lt 50 ]; do
        _call_attested
        _warmup=$((_warmup + 1))
    done

    # Measure hardware-backed TEE path timing
    _times=""
    _i=0
    while [ $_i -lt "$_sample_count" ]; do
        _start=$(_time_ns)
        _call_attested
        _end=$(_time_ns)
        _elapsed=$((_end - _start))
        _times="${_times}${_elapsed}
"
        _i=$((_i + 1))
    done

    # Sort and remove outliers
    _sorted=$(echo "$_times" | grep -v '^$' | _sort_numbers)
    _total=$(echo "$_sorted" | wc -l | tr -d ' ')
    _trimmed=$(echo "$_sorted" | _remove_outliers "$_total")

    # Compute mean and stddev (in nanoseconds, report in milliseconds)
    _mean_ns=$(echo "$_trimmed" | _calc_mean)
    _stddev_ns=$(echo "$_trimmed" | _calc_stddev)

    _mean_ms=$(awk "BEGIN { printf \"%.4f\", $_mean_ns / 1000000 }")
    _stddev_ms=$(awk "BEGIN { printf \"%.4f\", $_stddev_ns / 1000000 }")
    _calibrated_at=$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')

    # Save to config.json as referenceProfile
    _profile="{\"meanMs\": $_mean_ms, \"stddevMs\": $_stddev_ms, \"sampleCount\": $_sample_count, \"calibratedAt\": \"$_calibrated_at\"}"

    if [ -f "$CONFIG_FILE" ]; then
        # Replace referenceProfile value (handles null or existing object)
        _tmp_config="${CONFIG_FILE}.tmp"
        awk -v profile="$_profile" '
            /"referenceProfile"/ {
                # Handle single-line null case
                if ($0 ~ /null/) {
                    sub(/null/, profile)
                    print
                    next
                }
                # Handle single-line object case
                if ($0 ~ /\}/) {
                    sub(/\{[^}]*\}/, profile)
                    print
                    next
                }
                # Multi-line object: print replacement and skip until closing brace
                sub(/\{.*/, profile ",")
                print
                skip=1
                next
            }
            skip && /\}/ { skip=0; next }
            skip { next }
            { print }
        ' "$CONFIG_FILE" > "$_tmp_config"

        if [ -s "$_tmp_config" ]; then
            mv -f "$_tmp_config" "$CONFIG_FILE"
            chmod 0600 "$CONFIG_FILE" 2>/dev/null
        else
            rm -f "$_tmp_config" 2>/dev/null
            # Fallback: use sed for simple null replacement
            sed -i "s/\"referenceProfile\"[[:space:]]*:[[:space:]]*null/\"referenceProfile\": $_profile/" "$CONFIG_FILE"
        fi
    fi

    log_info "Calibration complete: mean=${_mean_ms}ms stddev=${_stddev_ms}ms samples=$_sample_count"
    echo "{\"status\": 0, \"data\": $_profile}"
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
        profiler_run)
            cmd_profiler_run "$_input"
            ;;
        profiler_reference)
            cmd_profiler_reference
            ;;
        profiler_calibrate)
            cmd_profiler_calibrate "$_input"
            ;;
        *)
            echo "{\"status\": 1, \"message\": \"Unknown command: $_command\"}"
            return 1
            ;;
    esac
}

# Run main dispatcher if executed directly (not sourced)
case "$0" in
    *latency_profiler.sh)
        _main "$1"
        ;;
esac
