#!/usr/bin/env python3
"""
Apply Latency Equalizer patch to TEESimulator's AttestationPatcher.kt

The patch wraps `patchCertificateChain` so that after the simulated chain is
built, a configurable wait time is inserted to bring the attested response
duration closer to the hardware-backed reference profile.

Configuration file: /data/adb/tricky_store/equalizer.conf
    enabled=true
    referenceMs=1.05
    stddevMs=0.08
    detectionThreshold=1.1
"""
import sys
import re
from pathlib import Path

PATCH_MARKER = '// === TEE Simulator Plus: Latency Equalizer ==='

# This Kotlin object is appended after the package + imports of AttestationPatcher.kt.
# We add it as a top-level object so it doesn't conflict with the existing object body.
EQUALIZER_OBJECT = r'''
// === TEE Simulator Plus: Latency Equalizer ===
// Reads /data/adb/tricky_store/equalizer.conf and inserts a Thread.sleep
// in the attestation patching path to mask timing differences between the
// real TEE and the software simulator.
private object LatencyEqualizer {
    private const val CONFIG_PATH = "/data/adb/tricky_store/equalizer.conf"
    @Volatile private var lastReadMs: Long = 0L
    @Volatile private var enabled: Boolean = false
    @Volatile private var referenceMs: Double = 0.0
    @Volatile private var stddevMs: Double = 0.0
    @Volatile private var detectionThreshold: Double = 1.1
    private val rng = java.util.Random()

    @Synchronized
    private fun reloadConfigIfStale() {
        val now = System.currentTimeMillis()
        if (now - lastReadMs < 5000L) return
        lastReadMs = now
        try {
            val f = java.io.File(CONFIG_PATH)
            if (!f.exists()) {
                enabled = false
                return
            }
            val map = HashMap<String, String>()
            f.readLines().forEach { line ->
                val s = line.trim()
                if (s.isEmpty() || s.startsWith("#")) return@forEach
                val eq = s.indexOf('=')
                if (eq > 0) {
                    map[s.substring(0, eq).trim()] = s.substring(eq + 1).trim()
                }
            }
            enabled = map["enabled"]?.lowercase() == "true"
            referenceMs = map["referenceMs"]?.toDoubleOrNull() ?: 0.0
            stddevMs = map["stddevMs"]?.toDoubleOrNull() ?: 0.0
            detectionThreshold = (map["detectionThreshold"]?.toDoubleOrNull() ?: 1.1).coerceAtLeast(1.01)
        } catch (t: Throwable) {
            enabled = false
        }
    }

    fun apply(elapsedMs: Double) {
        reloadConfigIfStale()
        if (!enabled || referenceMs <= 0.0) return
        // Target: keep ratio = nonAttestedMs / attestedMs <= detectionThreshold
        // Therefore attestedMs >= nonAttestedMs / detectionThreshold.
        // We treat referenceMs as the reference "non-attested" duration baseline.
        val targetMs = referenceMs / detectionThreshold
        var waitMs = targetMs - elapsedMs
        if (waitMs <= 0.0) return
        // Apply Gaussian jitter clipped to ±stddev
        if (stddevMs > 0.0) {
            val noise = rng.nextGaussian() * stddevMs
            waitMs += noise.coerceIn(-stddevMs, stddevMs)
        }
        if (waitMs > 0.0) {
            val totalNs = (waitMs * 1_000_000.0).toLong().coerceAtMost(50_000_000L) // cap 50ms safety
            val ms = totalNs / 1_000_000L
            val ns = (totalNs % 1_000_000L).toInt()
            try {
                Thread.sleep(ms, ns)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
            }
        }
    }
}
// === /TEE Simulator Plus ==='''


def patch_file(path: Path) -> None:
    src = path.read_text(encoding='utf-8')

    if PATCH_MARKER in src:
        print('Already patched, skipping')
        return

    # 1. Insert the LatencyEqualizer object after the imports.
    # Find the last import statement.
    import_pattern = re.compile(r'(^import\s+[^\n]+\n)+', re.MULTILINE)
    matches = list(import_pattern.finditer(src))
    if not matches:
        print('ERROR: cannot find import block in AttestationPatcher.kt')
        sys.exit(1)
    last_import_end = matches[-1].end()
    src = src[:last_import_end] + EQUALIZER_OBJECT + '\n' + src[last_import_end:]

    # 2. Wrap patchCertificateChain so it measures elapsed time and calls apply() before returning.
    # The function signature is:
    #     fun patchCertificateChain(originalChain: Array<Certificate>?, uid: Int): Array<Certificate> {
    #         ...
    #         return runCatching { ... }
    #             .getOrElse {
    #                 SystemLogger.error(...)
    #                 originalChain ?: emptyArray()
    #             }
    #     }
    #
    # Strategy: rename the original function, then insert a wrapper with the same signature
    # that records start time, calls the original, calls equalizer, returns the result.

    rename_pattern = re.compile(
        r'(\bfun\s+)patchCertificateChain(\s*\(originalChain:\s*Array<Certificate>\?,\s*uid:\s*Int\):\s*Array<Certificate>)'
    )
    new_src, count = rename_pattern.subn(r'\1__tspOriginalPatchCertificateChain\2', src, count=1)
    if count == 0:
        print('WARNING: patchCertificateChain signature not matched. Equalizer object inserted but not invoked.')
        path.write_text(src, encoding='utf-8')
        return
    src = new_src

    # 3. Find the closing brace of the AttestationPatcher object and insert a wrapper before it.
    # We append the wrapper right after the renamed function definition (or anywhere inside the object).
    # Simpler strategy: add the wrapper just before the LAST closing brace at column 0.
    wrapper = '''
    /**
     * Wrapper inserted by TEE Simulator Plus that calls the original patcher
     * then applies the latency equalizer before returning the patched chain.
     */
    fun patchCertificateChain(originalChain: Array<Certificate>?, uid: Int): Array<Certificate> {
        val __tspStart = System.nanoTime()
        val result = __tspOriginalPatchCertificateChain(originalChain, uid)
        val __tspElapsedMs = (System.nanoTime() - __tspStart) / 1_000_000.0
        LatencyEqualizer.apply(__tspElapsedMs)
        return result
    }
'''

    # Find the `object AttestationPatcher {` block and insert wrapper before its final closing brace.
    obj_match = re.search(r'object\s+AttestationPatcher\s*\{', src)
    if not obj_match:
        print('ERROR: cannot find AttestationPatcher object declaration')
        sys.exit(1)

    # Walk braces to find the matching close.
    start = obj_match.end()
    depth = 1
    i = start
    while i < len(src) and depth > 0:
        c = src[i]
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                # Insert wrapper before this brace
                src = src[:i] + wrapper + src[i:]
                break
        i += 1

    if depth != 0:
        print('ERROR: unmatched braces while locating AttestationPatcher end')
        sys.exit(1)

    path.write_text(src, encoding='utf-8')
    print(f'Patched: {path}')
    print('  + LatencyEqualizer object inserted')
    print('  + patchCertificateChain wrapper installed')


def main():
    if len(sys.argv) < 2:
        print('Usage: apply_latency_patch.py <path-to-AttestationPatcher.kt>')
        sys.exit(1)
    patch_file(Path(sys.argv[1]))


if __name__ == '__main__':
    main()
