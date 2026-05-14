#!/system/bin/sh
# TEE Simulator Plus — service.sh
# Runs after boot completion.

MODDIR="${0%/*}"
TRICKY_STORE_DIR="/data/adb/tricky_store"
LOGFILE="$MODDIR/logs/module.log"

mkdir -p "$MODDIR/logs" 2>/dev/null

# Skip if disabled
[ -f "$MODDIR/disable" ] && exit 0

_log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] service: $1" >> "$LOGFILE" 2>/dev/null
}

_log "waiting for boot completion"

# Wait for boot
WAIT=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ $WAIT -lt 90 ]; do
    sleep 1
    WAIT=$((WAIT + 1))
done

_log "boot completed (waited ${WAIT}s)"

# Pre-warming if reference profile exists
CONFIG_FILE="$MODDIR/config/config.json"
if [ -f "$CONFIG_FILE" ]; then
    _has_profile=$(grep '"referenceProfile"' "$CONFIG_FILE" 2>/dev/null | grep -v 'null' | head -1)
    if [ -n "$_has_profile" ]; then
        _log "executing pre-warming (50 keystore calls)"
        _i=0
        while [ $_i -lt 50 ]; do
            service call android.security.keystore2 1 > /dev/null 2>&1
            _i=$((_i + 1))
        done
        _log "pre-warming completed"
    fi
fi

_log "service started"
