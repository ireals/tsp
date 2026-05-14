#!/system/bin/sh
# TEE Simulator Plus - Post-FS-Data Script
# Runs early in boot before Zygote starts

MODDIR="${0%/*}"
LOGFILE="$MODDIR/logs/post-fs-data.log"

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
log_msg "TEE Simulator Plus: post-fs-data starting"

# ===== Load Configuration =====
CONFIG_FILE="$MODDIR/config/config.json"
TARGET_LIST=""

if [ -f "$CONFIG_FILE" ]; then
  # Parse target list from config (simple grep-based extraction for POSIX sh)
  TARGET_LIST=$(cat "$CONFIG_FILE" | tr -d '[:space:]' | sed -n 's/.*"targetList":\[\([^]]*\)\].*/\1/p' | tr ',' '\n' | tr -d '"')
  log_msg "Config loaded. Targets: $(echo "$TARGET_LIST" | tr '\n' ',' | sed 's/,$//')"
else
  log_msg "WARNING: Config file not found at $CONFIG_FILE"
fi

# ===== Prepare Zygisk/LSPlt Hook Registration =====
# Create marker file to signal that TEE Simulator Plus is active
MARKER_DIR="/data/adb/tee-simulator-plus"
mkdir -p "$MARKER_DIR"

# Write active marker
echo "1" > "$MARKER_DIR/active"

# Write target list for hook to read
if [ -n "$TARGET_LIST" ]; then
  echo "$TARGET_LIST" > "$MARKER_DIR/targets.txt"
  log_msg "Target list written to $MARKER_DIR/targets.txt"
else
  # Empty target list means hook all attestation calls
  : > "$MARKER_DIR/targets.txt"
  log_msg "No specific targets configured, marker file created empty"
fi

# Set system property to signal module is active (if permitted)
resetprop -n persist.tsp.active 1 2>/dev/null
if [ $? -eq 0 ]; then
  log_msg "System property persist.tsp.active set"
else
  log_msg "Could not set system property (non-critical)"
fi

# ===== Prepare Hook Environment =====
# Ensure the native library is accessible for Zygisk injection
if [ -d "$MODDIR/lib" ]; then
  chmod 755 "$MODDIR/lib"
  for lib in "$MODDIR/lib/"*.so; do
    if [ -f "$lib" ]; then
      chmod 644 "$lib"
    fi
  done
  log_msg "Native libraries prepared"
fi

log_msg "TEE Simulator Plus: post-fs-data completed"
