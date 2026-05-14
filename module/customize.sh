#!/system/bin/sh
# TEE Simulator Plus - Installation Script
# Compatible with KernelSU and Magisk

SKIPUNZIP=0

# ===== Environment Detection =====
TSP_ENV=""

if [ -n "$KSU" ] || [ -d "/data/adb/ksu/" ]; then
  TSP_ENV="kernelsu"
  ui_print "- Environment: KernelSU detected"
elif [ -n "$MAGISK_VER_CODE" ]; then
  TSP_ENV="magisk"
  ui_print "- Environment: Magisk v${MAGISK_VER_CODE} detected"
else
  abort "! Neither KernelSU nor Magisk detected. Aborting installation."
fi

# ===== API Level Check =====
API=$(getprop ro.build.version.sdk)
if [ -z "$API" ]; then
  API=0
fi

if [ "$API" -lt 29 ]; then
  abort "! Android API level $API is not supported. Minimum required: 29 (Android 10). Aborting."
fi
ui_print "- API level: $API"

# ===== Architecture Detection =====
if [ -n "$ARCH" ]; then
  TSP_ARCH="$ARCH"
else
  TSP_ARCH=$(getprop ro.product.cpu.abi)
fi

case "$TSP_ARCH" in
  arm64*|aarch64*)
    TSP_LIB_DIR="arm64-v8a"
    ;;
  arm*|armeabi*)
    TSP_LIB_DIR="armeabi-v7a"
    ;;
  *)
    abort "! Unsupported architecture: $TSP_ARCH. Aborting."
    ;;
esac
ui_print "- Architecture: $TSP_ARCH ($TSP_LIB_DIR)"

# ===== Module Files =====
# Files are auto-extracted by Magisk/KernelSU (SKIPUNZIP=0)
ui_print "- Module files extracted"

# ===== Copy Native Library =====
ui_print "- Installing native library for $TSP_LIB_DIR..."
if [ -d "$MODPATH/libs/$TSP_LIB_DIR" ]; then
  mkdir -p "$MODPATH/system/lib64"
  cp -f "$MODPATH/libs/$TSP_LIB_DIR/"*.so "$MODPATH/system/lib64/" 2>/dev/null
  # Also copy to module's own lib directory for direct use
  mkdir -p "$MODPATH/lib"
  cp -f "$MODPATH/libs/$TSP_LIB_DIR/"*.so "$MODPATH/lib/" 2>/dev/null
fi

# ===== Preserve Existing Config on Update =====
if [ -f "/data/adb/modules/tee-simulator-plus/config/config.json" ]; then
  ui_print "- Preserving existing configuration..."
  cp -f "/data/adb/modules/tee-simulator-plus/config/config.json" "$MODPATH/config/config.json"
fi

# ===== Set Permissions =====
ui_print "- Setting permissions..."

# Keyboxes directory - restricted access
set_perm_recursive "$MODPATH/keyboxes" 0 0 0700 0600

# Config directory - restricted access
set_perm_recursive "$MODPATH/config" 0 0 0700 0600

# Scripts - executable
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755

# Logs directory
set_perm_recursive "$MODPATH/logs" 0 0 0755 0644

# Native libraries
if [ -d "$MODPATH/lib" ]; then
  set_perm_recursive "$MODPATH/lib" 0 0 0755 0644
fi

# WebUI root (KernelSU)
if [ -d "$MODPATH/webroot" ]; then
  set_perm_recursive "$MODPATH/webroot" 0 0 0755 0644
fi

# ===== Installation Summary =====
ui_print ""
ui_print "============================================"
ui_print "  TEE Simulator Plus v1.0.0"
ui_print "============================================"
ui_print "  Environment : $TSP_ENV"
ui_print "  API Level   : $API"
ui_print "  Architecture: $TSP_ARCH"
ui_print "  Library Dir : $TSP_LIB_DIR"
ui_print "============================================"
ui_print ""
ui_print "- Installation complete!"
if [ "$TSP_ENV" = "kernelsu" ]; then
  ui_print "- WebUI available in KernelSU app"
fi
ui_print "- Please reboot to activate the module."
ui_print ""
