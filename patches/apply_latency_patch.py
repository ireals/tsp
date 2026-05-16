#!/usr/bin/env python3
"""
Apply Latency Equalizer patch to TEESimulator's AttestationPatcher.kt

Goal: make the attested response time of the simulated path indistinguishable
from a real hardware-backed Keystore attestation. We pad the simulator path
with Thread.sleep so total elapsed time matches the configured reference
profile (mean ± Gaussian jitter).

Configuration: /data/adb/tricky_store/equalizer.conf
    enabled=true
    targetMs=1.05         # target total response time (HW reference mean)
    stddevMs=0.08         # jitter range (HW reference stddev)
    maxWaitMs=50          # safety cap on sleep
"""
import sys
import re
from pathlib import Path

PATCH_MARKER = '// === TEE Simulator Plus: Latency Equalizer ==='

EQUALIZER_OBJECT = r'''
// === TEE Simulator Plus: Latency Equalizer ===
// Reads /data/adb/tricky_store/equalizer.conf and pads the attestation
// patching path with Thread.sleep so the simulated response time matches
// a hardware-backed Keystore reference profile.
//
// The goal is statistical indistinguishability: the simulator's response
// time distribution should match the hardware TEE's distribution within
// the configured jitter range, so timing-based detectors cannot tell them
// apart from observed latencies alone.
private object LatencyEqualizer {
    private const val CONFIG_PATH = "/data/adb/tricky_store/equalizer.conf"
    @Volatile private var lastReadMs: Long = 0L
    @Volatile private var enabled: Boolean = false
    @Volatile private var targetMs: Double = 0.0
    @Volatile private var stddevMs: Double = 0.0
    @Volatile private var maxWaitMs: Double = 50.0
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
            // Backward compat: support both targetMs (new) and referenceMs (old)
            targetMs = map["targetMs"]?.toDoubleOrNull()
                ?: map["referenceMs"]?.toDoubleOrNull()
                ?: 0.0
            stddevMs = map["stddevMs"]?.toDoubleOrNull() ?: 0.0
            maxWaitMs = map["maxWaitMs"]?.toDoubleOrNull() ?: 50.0
        } catch (t: Throwable) {
            enabled = false
        }
    }

    /**
     * Pad the elapsed time so total response time equals targetMs (+/- jitter).
     * If the simulator already took longer than targetMs we cannot speed it up
     * — the most we can do is not slow it down further. In that case we exit
     * without sleeping.
     */
    fun apply(elapsedMs: Double) {
        reloadConfigIfStale()
        if (!enabled || targetMs <= 0.0) return

        // Sample target with Gaussian jitter to match HW distribution
        val sampledTarget = if (stddevMs > 0.0) {
            val noise = (rng.nextGaussian() * stddevMs).coerceIn(-stddevMs * 3, stddevMs * 3)
            targetMs + noise
        } else {
            targetMs
        }

        var waitMs = sampledTarget - elapsedMs
        if (waitMs <= 0.0) return
        if (waitMs > maxWaitMs) waitMs = maxWaitMs

        val totalNs = (waitMs * 1_000_000.0).toLong()
        if (totalNs <= 0L) return
        val ms = totalNs / 1_000_000L
        val ns = (totalNs % 1_000_000L).toInt()
        try {
            Thread.sleep(ms, ns)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
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
    import_pattern = re.compile(r'(^import\s+[^\n]+\n)+', re.MULTILINE)
    matches = list(import_pattern.finditer(src))
    if not matches:
        print('ERROR: cannot find import block in AttestationPatcher.kt')
        sys.exit(1)
    last_import_end = matches[-1].end()
    src = src[:last_import_end] + EQUALIZER_OBJECT + '\n' + src[last_import_end:]

    # 2. Rename original patchCertificateChain
    rename_pattern = re.compile(
        r'(\bfun\s+)patchCertificateChain(\s*\(originalChain:\s*Array<Certificate>\?,\s*uid:\s*Int\):\s*Array<Certificate>)'
    )
    new_src, count = rename_pattern.subn(r'\1__tspOriginalPatchCertificateChain\2', src, count=1)
    if count == 0:
        print('WARNING: patchCertificateChain signature not matched. Equalizer object inserted but not invoked.')
        path.write_text(src, encoding='utf-8')
        return
    src = new_src

    # 3. Insert wrapper that times the call and applies equalizer
    wrapper = '''
    /**
     * Wrapper inserted by TEE Simulator Plus that calls the original patcher
     * then pads the response time to match the hardware reference profile.
     */
    fun patchCertificateChain(originalChain: Array<Certificate>?, uid: Int): Array<Certificate> {
        val __tspStart = System.nanoTime()
        val result = __tspOriginalPatchCertificateChain(originalChain, uid)
        val __tspElapsedMs = (System.nanoTime() - __tspStart) / 1_000_000.0
        LatencyEqualizer.apply(__tspElapsedMs)
        return result
    }
'''

    obj_match = re.search(r'object\s+AttestationPatcher\s*\{', src)
    if not obj_match:
        print('ERROR: cannot find AttestationPatcher object declaration')
        sys.exit(1)

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
