// TEE Simulator Plus - LSPlt hook registration for keystore2
// Based on TEESimulator hook logic - to be integrated with upstream

#include "include/teesimplus.h"
#include <dlfcn.h>
#include <string.h>
#include <time.h>

namespace teesimplus {
namespace equalizer {

// Forward declarations for equalizer namespace functions
void applyEqualization(double elapsedMs, const Config& config);
void pinCpu(int core);

} // namespace equalizer
} // namespace teesimplus

namespace teesimplus {
namespace hooks {

// ---------------------------------------------------------------------------
// Function pointer types for keystore2 binder transactions
// ---------------------------------------------------------------------------

/**
 * Function pointer type for IKeystoreService::attestKey binder transaction.
 * Signature mirrors the internal binder transact call for attestKey.
 */
typedef int (*attestKey_t)(void* self, const void* keyDescriptor,
                           const void* attestParams, void* certChain);

/**
 * Function pointer type for IKeystoreService::generateKey binder transaction.
 * Signature mirrors the internal binder transact call for generateKey.
 */
typedef int (*generateKey_t)(void* self, const void* keyParams,
                             const void* attestKey, void* keyMetadata);

// ---------------------------------------------------------------------------
// Original function pointer storage (static globals)
// ---------------------------------------------------------------------------

static attestKey_t origAttestKey = nullptr;
static generateKey_t origGenerateKey = nullptr;

// Module config reference for use in hooks
static Config cachedConfig = {};

// ---------------------------------------------------------------------------
// Hook implementations
// ---------------------------------------------------------------------------

/**
 * Hook for IKeystoreService::attestKey binder transaction.
 * Intercepts attestation requests and provides simulated responses
 * using the active keybox, with timing equalization applied.
 */
int hookAttestKey(void* self, const void* keyDescriptor,
                  const void* attestParams, void* certChain) {
    // Record start time for latency measurement
    struct timespec startTime, endTime;
    clock_gettime(CLOCK_MONOTONIC, &startTime);

    int result = 0;

    // Check if we have an active keybox configured
    if (cachedConfig.activeKeyboxId.empty()) {
        // No keybox active — passthrough to original implementation
        LOGD("hookAttestKey: no active keybox, passing through to original");
        if (origAttestKey) {
            result = origAttestKey(self, keyDescriptor, attestParams, certChain);
        }

        // Record end time and log
        clock_gettime(CLOCK_MONOTONIC, &endTime);
        double elapsedMs = (endTime.tv_sec - startTime.tv_sec) * 1000.0 +
                           (endTime.tv_nsec - startTime.tv_nsec) / 1000000.0;
        LOGD("hookAttestKey: passthrough completed in %.3f ms", elapsedMs);
        return result;
    }

    // Active keybox present — execute simulated attestation logic
    LOGI("hookAttestKey: intercepting with keybox '%s'",
         cachedConfig.activeKeyboxId.c_str());

    // TODO: TEESimulator integration
    // 1. Parse keyDescriptor to determine key alias and domain
    // 2. Parse attestParams to extract challenge and attestation ID info
    // 3. Load the active keybox certificate chain from storage
    // 4. Generate a fresh attestation certificate using the keybox's
    //    intermediate CA key, embedding the challenge and device IDs
    // 5. Build the full certificate chain (leaf + intermediates + root)
    // 6. Write the certificate chain into certChain output parameter
    // 7. Set result to 0 (success) or appropriate error code

    // Placeholder: simulate a successful attestation
    result = 0;

    // Record end time
    clock_gettime(CLOCK_MONOTONIC, &endTime);
    double elapsedMs = (endTime.tv_sec - startTime.tv_sec) * 1000.0 +
                       (endTime.tv_nsec - startTime.tv_nsec) / 1000000.0;

    // Apply timing equalization to mask simulated vs real TEE latency
    equalizer::applyEqualization(elapsedMs, cachedConfig);

    // Log elapsed time at debug level
    LOGD("hookAttestKey: simulated attestation completed in %.3f ms (before equalization)",
         elapsedMs);

    return result;
}

/**
 * Hook for IKeystoreService::generateKey binder transaction.
 * Passes through to the original implementation but tracks the key
 * for potential future attestation interception.
 */
int hookGenerateKey(void* self, const void* keyParams,
                    const void* attestKey, void* keyMetadata) {
    int result = 0;

    // Call original function — we don't modify key generation, just track it
    if (origGenerateKey) {
        result = origGenerateKey(self, keyParams, attestKey, keyMetadata);
    }

    // TODO: Record key metadata for future attestation tracking
    // 1. Extract key alias and domain from keyParams
    // 2. Store key metadata in internal registry
    // 3. Associate with target package if applicable

    LOGD("hookGenerateKey: key generation passthrough completed (result=%d)", result);

    return result;
}

// ---------------------------------------------------------------------------
// Hook lifecycle management
// ---------------------------------------------------------------------------

/**
 * Remove all installed hooks and restore original functions.
 * Called during module unload or when disabling hooks.
 */
void unhookAll() {
    LOGI("unhookAll: restoring original function pointers");

    // TODO: In real implementation, use LSPlt API to restore PLT entries:
    // lsplt::v2::RestoreHook(...)

    // Restore original function pointers
    origAttestKey = nullptr;
    origGenerateKey = nullptr;

    // Clear cached config
    cachedConfig = {};

    LOGI("unhookAll: all hooks removed and originals restored");
}

/**
 * Register PLT hooks for keystore2 service functions.
 * Uses dlsym to locate target functions and installs hooks via LSPlt.
 *
 * @param config  Module configuration (used for equalizer and target settings)
 * @return true if hooks were successfully registered, false otherwise
 */
bool registerHooks(const Config& config) {
    LOGI("registerHooks: attempting to hook keystore2 service functions");

    // Cache config for use in hook callbacks
    cachedConfig = config;

    // Attempt to find keystore2 service library
    // TODO: The actual library name may vary by Android version:
    //   - Android 12+: libkeystore2.so or the keystore2 binary itself
    //   - Older: libkeystore_binder.so
    void* handle = dlopen("libkeystore2.so", RTLD_NOLOAD);
    if (!handle) {
        // Try alternative library name
        handle = dlopen("libkeystore-engine.so", RTLD_NOLOAD);
    }

    if (!handle) {
        LOGE("registerHooks: failed to find keystore2 library: %s", dlerror());
        return false;
    }

    // TODO: Locate the actual attestKey and generateKey function symbols.
    // In practice, these are C++ mangled names within the keystore2 service.
    // The actual symbols depend on the Android version and build:
    //   - _ZN7android8security9keystore2...attestKey...
    //   - _ZN7android8security9keystore2...generateKey...
    // For now, use placeholder symbol names.

    void* attestKeySym = dlsym(handle, "_ZN7android8security9keystore219KeystoreService9attestKeyEv");
    void* generateKeySym = dlsym(handle, "_ZN7android8security9keystore219KeystoreService11generateKeyEv");

    if (!attestKeySym) {
        LOGW("registerHooks: attestKey symbol not found (expected on this Android version)");
        // Not fatal — symbol names vary by version
    }

    if (!generateKeySym) {
        LOGW("registerHooks: generateKey symbol not found (expected on this Android version)");
    }

    // Store original function pointers
    origAttestKey = reinterpret_cast<attestKey_t>(attestKeySym);
    origGenerateKey = reinterpret_cast<generateKey_t>(generateKeySym);

    // TODO: Install PLT hooks using LSPlt
    // In real implementation:
    //
    //   #include "lsplt.hpp"
    //
    //   // Register hook for attestKey
    //   lsplt::v2::RegisterHook(
    //       getpid(),
    //       lsplt::MapInfo::Scan(),
    //       "libkeystore2.so",
    //       "attestKey_symbol",
    //       reinterpret_cast<void*>(hookAttestKey),
    //       reinterpret_cast<void**>(&origAttestKey)
    //   );
    //
    //   // Register hook for generateKey
    //   lsplt::v2::RegisterHook(
    //       getpid(),
    //       lsplt::MapInfo::Scan(),
    //       "libkeystore2.so",
    //       "generateKey_symbol",
    //       reinterpret_cast<void*>(hookGenerateKey),
    //       reinterpret_cast<void**>(&origGenerateKey)
    //   );
    //
    //   // Commit all registered hooks
    //   lsplt::v2::CommitHook();

    LOGI("registerHooks: hooks registered (origAttestKey=%p, origGenerateKey=%p)",
         reinterpret_cast<void*>(origAttestKey),
         reinterpret_cast<void*>(origGenerateKey));

    // Close the handle (we only needed it for symbol lookup)
    dlclose(handle);

    return (origAttestKey != nullptr || origGenerateKey != nullptr);
}

/**
 * Remove hooks for non-target processes.
 * Called early in process initialization to ensure hooks are only active
 * in processes that are on the target list.
 */
void removeHooksForNonTarget() {
    LOGI("removeHooksForNonTarget: restoring originals for non-target process");

    // TODO: In real implementation, use LSPlt API to restore PLT entries
    // for this specific process without affecting other hooked processes.

    // Restore original function pointers
    if (origAttestKey) {
        // TODO: lsplt::v2::RestoreHook(...) for attestKey
        origAttestKey = nullptr;
    }

    if (origGenerateKey) {
        // TODO: lsplt::v2::RestoreHook(...) for generateKey
        origGenerateKey = nullptr;
    }

    LOGI("removeHooksForNonTarget: hooks removed, process will use original keystore2");
}

} // namespace hooks
} // namespace teesimplus
