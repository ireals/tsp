#!/usr/bin/env python3
"""
Apply Latency Equalizer patch to TrickyStore's KeystoreInterceptor.kt

The patch adds a timing equalization step inside onPostTransact, just before
returning OverrideReply with the hacked certificate chain. The equalizer reads
configuration from /data/adb/tricky_store/equalizer.conf and inserts a sleep
to make the attested response time match a reference profile.

Configuration file format (line-based key=value):
    enabled=true
    referenceMs=1.05
    stddevMs=0.08
    detectionThreshold=1.1
"""
import sys
import re
from pathlib import Path

LATENCY_CODE = '''
    // ===== TEE Simulator Plus: Latency Equalizer =====
    // Reads /data/adb/tricky_store/equalizer.conf and inserts a wait
    // before returning hacked attestation responses to mask timing differences.
    private object LatencyEqualizer {
        private const val CONFIG_PATH = "/data/adb/tricky_store/equalizer.conf"
        private var lastReadMs = 0L
        private var enabled = false
        private var referenceMs = 0.0
        private var stddevMs = 0.0
        private var detectionThreshold = 1.1
        private val rng = java.util.Random()

        @Synchronized
        private fun reloadConfig() {
            val now = System.currentTimeMillis()
            if (now - lastReadMs < 5000) return
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
                    val idx = s.indexOf('=')
                    if (idx > 0) {
                        map[s.substring(0, idx).trim()] = s.substring(idx + 1).trim()
                    }
                }
                enabled = map["enabled"]?.lowercase() == "true"
                referenceMs = map["referenceMs"]?.toDoubleOrNull() ?: 0.0
                stddevMs = map["stddevMs"]?.toDoubleOrNull() ?: 0.0
                detectionThreshold = map["detectionThreshold"]?.toDoubleOrNull() ?: 1.1
            } catch (t: Throwable) {
                Logger.e("LatencyEqualizer: failed to read config", t)
                enabled = false
            }
        }

        fun apply(elapsedMs: Double) {
            reloadConfig()
            if (!enabled || referenceMs <= 0.0) return
            // Target: make hacked path take at least referenceMs / detectionThreshold
            // (so non-attested / attested ratio stays under detectionThreshold)
            val targetMs = referenceMs / detectionThreshold
            var waitMs = targetMs - elapsedMs
            if (waitMs <= 0.0) return
            // Add jitter within ±stddev to avoid fixed-value detection signature
            if (stddevMs > 0.0) {
                waitMs += (rng.nextGaussian() * stddevMs).coerceIn(-stddevMs, stddevMs)
            }
            if (waitMs > 0.0) {
                try {
                    val ns = (waitMs * 1_000_000.0).toLong()
                    val ms = ns / 1_000_000L
                    val rest = (ns % 1_000_000L).toInt()
                    Thread.sleep(ms, rest)
                } catch (_: InterruptedException) {
                    Thread.currentThread().interrupt()
                }
            }
        }
    }
    // ===== /TEE Simulator Plus =====

'''

# Inject a timing measurement around the cert-chain-hack in onPostTransact
# We replace the original return-success path with one that records elapsed
# time and calls LatencyEqualizer.apply() before returning.
PATCH_HEADER_MARKER = '@SuppressLint("BlockedPrivateApi")\nobject KeystoreInterceptor : BinderInterceptor() {'

def patch_file(path: Path) -> None:
    src = path.read_text(encoding='utf-8')

    if 'TEE Simulator Plus: Latency Equalizer' in src:
        print('Already patched, skipping')
        return

    # 1. Inject the LatencyEqualizer object inside the KeystoreInterceptor class
    if PATCH_HEADER_MARKER not in src:
        print(f'ERROR: cannot find marker in {path}')
        sys.exit(1)
    src = src.replace(
        PATCH_HEADER_MARKER,
        PATCH_HEADER_MARKER + LATENCY_CODE,
        1,
    )

    # 2. Wrap the cert chain hack with timing measurement
    # The original block we target:
    #     val newChain = CertHack.hackCertificateChain(chain)
    #     Utils.putCertificateChain(response, newChain)
    #     Logger.i("hacked cert of uid=$callingUid")
    #     p.writeNoException()
    #     p.writeTypedObject(response, 0)
    #     return OverrideReply(0, p)
    pattern = re.compile(
        r'(val\s+newChain\s*=\s*CertHack\.hackCertificateChain\(chain\)\s*\n'
        r'\s*Utils\.putCertificateChain\(response,\s*newChain\)\s*\n'
        r'\s*Logger\.i\("hacked cert of uid=\$callingUid"\)\s*\n'
        r'\s*p\.writeNoException\(\)\s*\n'
        r'\s*p\.writeTypedObject\(response,\s*0\)\s*\n'
        r'\s*return\s+OverrideReply\(0,\s*p\))'
    )

    def replacer(m: re.Match) -> str:
        return (
            'val __tspStart = System.nanoTime()\n'
            '                val newChain = CertHack.hackCertificateChain(chain)\n'
            '                Utils.putCertificateChain(response, newChain)\n'
            '                Logger.i("hacked cert of uid=$callingUid")\n'
            '                p.writeNoException()\n'
            '                p.writeTypedObject(response, 0)\n'
            '                val __tspElapsedMs = (System.nanoTime() - __tspStart) / 1_000_000.0\n'
            '                LatencyEqualizer.apply(__tspElapsedMs)\n'
            '                return OverrideReply(0, p)'
        )

    new_src, count = pattern.subn(replacer, src)
    if count == 0:
        print('WARNING: cert chain hack pattern not matched; equalizer object injected but not invoked')
        print('         The build will succeed but latency equalizer will not run.')
    else:
        print(f'Patched {count} call site(s) with latency measurement')
        src = new_src

    path.write_text(src, encoding='utf-8')
    print(f'Patched: {path}')


def main():
    if len(sys.argv) < 2:
        print('Usage: apply_latency_patch.py <path-to-KeystoreInterceptor.kt>')
        sys.exit(1)
    patch_file(Path(sys.argv[1]))


if __name__ == '__main__':
    main()
