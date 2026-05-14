#define _GNU_SOURCE
#include "include/teesimplus.h"
#include <time.h>
#include <stdlib.h>
#include <sched.h>
#include <unistd.h>

namespace teesimplus {
namespace equalizer {

/**
 * Apply latency equalization to make simulated TEE operations
 * indistinguishable from real hardware TEE timing.
 *
 * @param elapsedMs  Actual elapsed time of the simulated operation in milliseconds
 * @param config     Module configuration containing equalizer parameters
 */
void applyEqualization(double elapsedMs, const Config& config) {
    if (!config.equalizerEnabled) {
        LOGD("Equalizer disabled, skipping");
        return;
    }

    if (!config.hasProfile) {
        LOGW("No reference profile available, cannot equalize timing");
        return;
    }

    // T_n_estimate from reference profile (mean hardware TEE latency)
    double T_n_estimate = config.referenceProfile.mean;

    // Calculate target time based on detection threshold
    double targetTime = T_n_estimate / config.detectionThreshold;

    // Calculate required wait time
    double waitTime = targetTime - elapsedMs;
    if (waitTime < 0.0) {
        waitTime = 0.0;
    }

    // Add jitter: random value in [-stddev, +stddev]
    double stddev = config.referenceProfile.stddev;
    double jitter = ((double)rand() / RAND_MAX) * 2.0 * stddev - stddev;
    waitTime += jitter;

    if (waitTime > 0.0) {
        // Convert milliseconds to nanoseconds for nanosleep
        long waitNs = (long)(waitTime * 1000000.0);
        struct timespec ts;
        ts.tv_sec = waitNs / 1000000000L;
        ts.tv_nsec = waitNs % 1000000000L;

        LOGD("Equalizer: elapsed=%.3fms target=%.3fms wait=%.3fms jitter=%.3fms",
             elapsedMs, targetTime, waitTime, jitter);

        nanosleep(&ts, nullptr);
    } else {
        LOGD("Equalizer: elapsed=%.3fms exceeds target, no wait needed", elapsedMs);
    }
}

/**
 * Pin the current thread to a specific CPU core.
 * This reduces timing variance caused by core migration.
 *
 * @param core  CPU core number to pin to (0-indexed)
 */
void pinCpu(int core) {
    cpu_set_t cpuset;
    CPU_ZERO(&cpuset);
    CPU_SET(core, &cpuset);

    if (sched_setaffinity(0, sizeof(cpu_set_t), &cpuset) == 0) {
        LOGI("Pinned to CPU core %d", core);
    } else {
        LOGE("Failed to pin to CPU core %d", core);
    }
}

} // namespace equalizer
} // namespace teesimplus
