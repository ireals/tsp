#!/bin/bash
# TEE Simulator Plus — Build script
# Requires: Android NDK (set ANDROID_NDK_HOME or NDK_HOME)

set -e

# Find NDK
NDK="${ANDROID_NDK_HOME:-${NDK_HOME:-$HOME/Android/Sdk/ndk/26.1.10909125}}"
if [ ! -d "$NDK" ]; then
    echo "ERROR: Android NDK not found at $NDK"
    echo "Set ANDROID_NDK_HOME environment variable to your NDK path"
    exit 1
fi

echo "Using NDK: $NDK"

# Build native library
echo "=== Building native library ==="
cd module/native
"$NDK/ndk-build" NDK_PROJECT_PATH=. APP_BUILD_SCRIPT=jni/Android.mk NDK_APPLICATION_MK=jni/Application.mk -j$(nproc)

# Copy built libraries
echo "=== Copying libraries ==="
mkdir -p ../libs/arm64-v8a ../libs/armeabi-v7a
cp libs/arm64-v8a/libteesimplus.so ../libs/arm64-v8a/ 2>/dev/null && echo "  arm64-v8a: OK" || echo "  arm64-v8a: SKIP"
cp libs/armeabi-v7a/libteesimplus.so ../libs/armeabi-v7a/ 2>/dev/null && echo "  armeabi-v7a: OK" || echo "  armeabi-v7a: SKIP"
cd ../..

# Package zip
echo "=== Packaging module zip ==="
cd module
rm -f ../tee-simulator-plus-v1.0.0.zip
zip -r ../tee-simulator-plus-v1.0.0.zip \
    META-INF/ \
    module.prop \
    customize.sh \
    post-fs-data.sh \
    service.sh \
    sepolicy.rule \
    config/ \
    docs/ \
    keyboxes/ \
    libs/ \
    logs/ \
    scripts/ \
    webroot/ \
    -x "*.gitkeep"
cd ..

echo ""
echo "=== Build complete ==="
echo "Output: tee-simulator-plus-v1.0.0.zip"
ls -la tee-simulator-plus-v1.0.0.zip
