#!/system/bin/sh
# TEE Simulator Plus — Latency profiler

MODDIR="${MODDIR:-/data/adb/modules/tee-simulator-plus}"
CONFIG_FILE="$MODDIR/config/config.json"
LOG_FILE="$MODDIR/logs/module.log"

mkdir -p "$MODDIR/logs" 2>/dev/null

_json_get_str() {
    echo "$1" | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
}

_json_get_num() {
    echo "$1" | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\([0-9.]*\).*/\1/p" | head -1
}

_log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null) [INFO] profiler: $1" >> "$LOG_FILE" 2>/dev/null
}

_read_threshold() {
    if [ -f "$CONFIG_FILE" ]; then
        _v=$(grep '"detectionThreshold"' "$CONFIG_FILE" | sed 's/.*:[[:space:]]*\([0-9.]*\).*/\1/')
        echo "${_v:-1.1}"
    else
        echo "1.1"
    fi
}

_time_ns() {
    _t=$(date '+%s%N' 2>/dev/null)
    if [ -n "$_t" ] && [ ${#_t} -gt 10 ]; then
        echo "$_t"
    else
        # Fallback: read from /proc/uptime in seconds, scaled to ns
        awk 'BEGIN{srand()} END{printf "%.0f\n", systime()*1000000000 + rand()*1000000}' < /dev/null 2>/dev/null || echo 0
    fi
}

_call_attested() {
    service call android.security.keystore2 1 > /dev/null 2>&1
}

_call_non_attested() {
    service call android.security.keystore2 2 > /dev/null 2>&1
}

cmd_profiler_run() {
    _samples=$(_json_get_num "$1" "sampleCount")
    [ -z "$_samples" ] && _samples=500
    _cpu=$(_json_get_num "$1" "cpuCore")
    [ -z "$_cpu" ] && _cpu=0

    _log "Run: samples=$_samples cpu=$_cpu"

    # CPU pinning (best effort)
    taskset -p "$(printf '%x' $((1 << _cpu)))" $$ > /dev/null 2>&1

    # Pre-warm
    _i=0
    while [ $_i -lt 50 ]; do
        _call_attested
        _i=$((_i + 1))
    done

    # Measure attested
    _attested_file="/data/local/tmp/tsp_attested.$$"
    _i=0
    : > "$_attested_file"
    while [ $_i -lt "$_samples" ]; do
        _s=$(_time_ns)
        _call_attested
        _e=$(_time_ns)
        echo $((_e - _s)) >> "$_attested_file"
        _i=$((_i + 1))
    done

    # Measure non-attested
    _na_file="/data/local/tmp/tsp_na.$$"
    _i=0
    : > "$_na_file"
    while [ $_i -lt "$_samples" ]; do
        _s=$(_time_ns)
        _call_non_attested
        _e=$(_time_ns)
        echo $((_e - _s)) >> "$_na_file"
        _i=$((_i + 1))
    done

    # Sort and trim 5% top/bottom
    _trim=$(awk "BEGIN{t=int($_samples*0.05); if(t<1)t=1; print t}")
    _att_trim=$(sort -n "$_attested_file" | awk -v t=$_trim -v n=$_samples 'NR>t && NR<=n-t')
    _na_trim=$(sort -n "$_na_file" | awk -v t=$_trim -v n=$_samples 'NR>t && NR<=n-t')

    # Compute means in nanoseconds
    _ta_ns=$(echo "$_att_trim" | awk '{s+=$1; c++} END{if(c>0) printf "%.0f", s/c; else print 0}')
    _tn_ns=$(echo "$_na_trim" | awk '{s+=$1; c++} END{if(c>0) printf "%.0f", s/c; else print 0}')

    # Convert to ms
    _ta=$(awk "BEGIN{printf \"%.4f\", $_ta_ns/1000000}")
    _tn=$(awk "BEGIN{printf \"%.4f\", $_tn_ns/1000000}")
    _diff=$(awk "BEGIN{printf \"%.4f\", ($_ta_ns - $_tn_ns)/1000000}")
    _ratio=$(awk "BEGIN{if($_ta_ns>0) printf \"%.4f\", $_tn_ns/$_ta_ns; else print 0}")

    _filtered=$((_trim * 4))   # top+bottom for both arrays
    _total=$((_samples * 2))

    _threshold=$(_read_threshold)
    _judgment=$(awk "BEGIN{if($_ratio > $_threshold) print \"Positive\"; else print \"Negative\"}")

    _log "Register timer bound_cpu${_cpu} attested ${_ta}ms non-attested ${_tn}ms diff ${_diff}ms ratio ${_ratio}x filteredBadSamples=${_filtered}/${_total} threshold > ${_threshold}x ${_judgment}"

    rm -f "$_attested_file" "$_na_file" 2>/dev/null

    echo "{\"status\":0,\"data\":{\"cpuCore\":$_cpu,\"sampleCount\":$_samples,\"attestedMeanMs\":$_ta,\"nonAttestedMeanMs\":$_tn,\"diffMs\":$_diff,\"ratio\":$_ratio,\"filteredBadSamples\":$_filtered,\"totalSamples\":$_total,\"threshold\":$_threshold,\"judgment\":\"$_judgment\"}}"
}

cmd_profiler_reference() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo '{"status":0,"data":null}'
        return 0
    fi
    _ref=$(awk '/"referenceProfile"/{
        if($0 ~ /null/){print "null"; exit}
        s=$0; in_obj=1; next
    } in_obj{
        s=s $0
        if($0 ~ /\}/){print s; exit}
    }' "$CONFIG_FILE")
    [ -z "$_ref" ] && _ref="null"
    echo "{\"status\":0,\"data\":$_ref}"
}

cmd_profiler_calibrate() {
    _samples=$(_json_get_num "$1" "sampleCount")
    [ -z "$_samples" ] && _samples=500

    _log "Calibrate: samples=$_samples"

    _i=0
    while [ $_i -lt 50 ]; do
        _call_attested
        _i=$((_i + 1))
    done

    _f="/data/local/tmp/tsp_cal.$$"
    : > "$_f"
    _i=0
    while [ $_i -lt "$_samples" ]; do
        _s=$(_time_ns)
        _call_attested
        _e=$(_time_ns)
        echo $((_e - _s)) >> "$_f"
        _i=$((_i + 1))
    done

    _trim=$(awk "BEGIN{t=int($_samples*0.05); if(t<1)t=1; print t}")
    _data=$(sort -n "$_f" | awk -v t=$_trim -v n=$_samples 'NR>t && NR<=n-t')

    _mean_ns=$(echo "$_data" | awk '{s+=$1; c++} END{if(c>0) printf "%.0f", s/c; else print 0}')
    _stddev_ns=$(echo "$_data" | awk -v m=$_mean_ns '{s+=($1-m)*($1-m); c++} END{if(c>1) printf "%.0f", sqrt(s/(c-1)); else print 0}')

    _mean_ms=$(awk "BEGIN{printf \"%.4f\", $_mean_ns/1000000}")
    _stddev_ms=$(awk "BEGIN{printf \"%.4f\", $_stddev_ns/1000000}")

    rm -f "$_f"

    # Save reference profile to config
    _profile="{\"meanMs\":$_mean_ms,\"stddevMs\":$_stddev_ms,\"sampleCount\":$_samples}"
    if [ -f "$CONFIG_FILE" ]; then
        _tmp="${CONFIG_FILE}.tmp"
        awk -v p="$_profile" '
        BEGIN{done=0}
        /"referenceProfile"/{
            if(done){print; next}
            sub(/"referenceProfile"[[:space:]]*:[[:space:]]*[^,}]*/, "\"referenceProfile\": " p)
            done=1
            print
            next
        }
        {print}' "$CONFIG_FILE" > "$_tmp" && mv -f "$_tmp" "$CONFIG_FILE"
        chmod 0644 "$CONFIG_FILE"
    fi

    _log "Calibration: mean=${_mean_ms}ms stddev=${_stddev_ms}ms"
    echo "{\"status\":0,\"data\":{\"meanMs\":$_mean_ms,\"stddevMs\":$_stddev_ms,\"sampleCount\":$_samples}}"
}

# Dispatcher
_input="$1"
_command=$(_json_get_str "$_input" "command")

case "$_command" in
    profiler_run)       cmd_profiler_run "$_input" ;;
    profiler_reference) cmd_profiler_reference ;;
    profiler_calibrate) cmd_profiler_calibrate "$_input" ;;
    *) echo "{\"status\":1,\"message\":\"Unknown: $_command\"}" ;;
esac
