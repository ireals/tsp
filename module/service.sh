#!/system/bin/sh
# TEE Simulator Plus - Service Script
# Runs after boot is completed

MODDIR="${0%/*}"
LOGFILE="$MODDIR/logs/service.log"

# ===== Check if Module is Enabled =====
if [ -f "$MODDIR/disable" ]; then
  exit 0
fi

# ===== Logging Helper =====
log_msg() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOGFILE"
}

# Ensure log directory exists
mkdir -p "$MODDIR/logs"

# ===== Wait for Boot Completion =====
log_msg "TEE Simulator Plus: service.sh waiting for boot..."

BOOT_COMPLETED=0
WAIT_COUNT=0
MAX_WAIT=60

while [ "$BOOT_COMPLETED" -eq 0 ] && [ "$WAIT_COUNT" -lt "$MAX_WAIT" ]; do
  BOOT_COMPLETED=$(getprop sys.boot_completed)
  if [ "$BOOT_COMPLETED" != "1" ]; then
    BOOT_COMPLETED=0
    sleep 1
    WAIT_COUNT=$((WAIT_COUNT + 1))
  else
    BOOT_COMPLETED=1
  fi
done

if [ "$BOOT_COMPLETED" -ne 1 ]; then
  log_msg "WARNING: Boot completion timeout after ${MAX_WAIT}s, proceeding anyway"
fi

log_msg "TEE Simulator Plus: boot completed, starting service"

# ===== Load Configuration Store =====
CONFIG_FILE="$MODDIR/config/config.json"
REFERENCE_PROFILE=""
LATENCY_ENABLED=""
LOG_LEVEL=""

if [ -f "$CONFIG_FILE" ]; then
  # Parse configuration values (POSIX-compatible JSON parsing)
  REFERENCE_PROFILE=$(cat "$CONFIG_FILE" | tr -d '[:space:]' | sed -n 's/.*"referenceProfile":\([^,}]*\).*/\1/p')
  LATENCY_ENABLED=$(cat "$CONFIG_FILE" | tr -d '[:space:]' | sed -n 's/.*"latencyEqualizerEnabled":\([^,}]*\).*/\1/p')
  LOG_LEVEL=$(cat "$CONFIG_FILE" | tr -d '[:space:]' | sed -n 's/.*"logLevel":"\([^"]*\)".*/\1/p')

  log_msg "Configuration loaded:"
  log_msg "  referenceProfile: $REFERENCE_PROFILE"
  log_msg "  latencyEqualizerEnabled: $LATENCY_ENABLED"
  log_msg "  logLevel: $LOG_LEVEL"
else
  log_msg "WARNING: Config file not found at $CONFIG_FILE"
fi

# ===== Pre-warming: Execute Dummy Keystore Calls =====
if [ "$REFERENCE_PROFILE" != "null" ] && [ -n "$REFERENCE_PROFILE" ]; then
  log_msg "Reference profile detected, executing pre-warming (50 dummy keystore calls)..."

  PREWARM_COUNT=0
  PREWARM_TARGET=50

  while [ "$PREWARM_COUNT" -lt "$PREWARM_TARGET" ]; do
    # Trigger a lightweight keystore operation to warm up the TEE path
    # This helps establish a baseline latency profile
    cmd keystore2 get-state >/dev/null 2>&1 || \
      service call android.security.keystore2 1 >/dev/null 2>&1 || \
      true
    PREWARM_COUNT=$((PREWARM_COUNT + 1))
  done

  log_msg "Pre-warming completed: $PREWARM_COUNT keystore calls executed"
else
  log_msg "No reference profile configured, skipping pre-warming"
fi

# ===== Start Background Services =====
# Set runtime properties
resetprop -n persist.tsp.service_running 1 2>/dev/null
resetprop -n persist.tsp.boot_time "$(date '+%s')" 2>/dev/null

# Create PID file for service tracking
echo "$$" > "$MODDIR/logs/service.pid"

# ===== Latency Equalizer Initialization =====
if [ "$LATENCY_ENABLED" = "true" ]; then
  log_msg "Latency equalizer enabled, initializing..."
  # Write equalizer state marker for the native hook to read
  MARKER_DIR="/data/adb/tee-simulator-plus"
  mkdir -p "$MARKER_DIR"
  echo "1" > "$MARKER_DIR/equalizer_active"
  log_msg "Latency equalizer marker set"
else
  log_msg "Latency equalizer disabled"
fi

log_msg "TEE Simulator Plus: service started successfully (PID: $$)"
