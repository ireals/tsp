#ifndef TEESIMPLUS_H
#define TEESIMPLUS_H

#include <jni.h>
#include <string>
#include <vector>
#include <android/log.h>

#define LOG_TAG "TEESimulatorPlus"

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)

namespace teesimplus {

struct Config {
    bool equalizerEnabled;
    double detectionThreshold;
    struct {
        double mean;
        double stddev;
    } referenceProfile;
    bool hasProfile;
    std::string activeKeyboxId;
    std::vector<std::string> targetList;
};

Config loadConfig(const char* path);
bool isTargetProcess(const char* packageName, const Config& config);

} // namespace teesimplus

#endif // TEESIMPLUS_H
