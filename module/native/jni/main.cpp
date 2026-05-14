#include "include/teesimplus.h"
#include "include/zygisk.hpp"

#include <cstdio>
#include <cstring>
#include <cstdlib>

#define MODULE_PATH "/data/adb/modules/tee-simulator-plus"
#define CONFIG_PATH MODULE_PATH "/config/config.json"

using namespace teesimplus;

// Forward declarations for hook.cpp functions
namespace teesimplus {
namespace hooks {
    bool registerHooks(const Config& config);
    void unhookAll();
    void removeHooksForNonTarget();
} // namespace hooks
} // namespace teesimplus

// ============================================================================
// Config loading — simple JSON parser (no external library)
// ============================================================================
namespace teesimplus {

static const char* findJsonValue(const char* json, const char* key) {
    char searchKey[256];
    snprintf(searchKey, sizeof(searchKey), "\"%s\"", key);
    const char* pos = strstr(json, searchKey);
    if (!pos) return nullptr;
    pos += strlen(searchKey);
    while (*pos && (*pos == ' ' || *pos == '\t' || *pos == '\n' || *pos == '\r' || *pos == ':')) {
        pos++;
    }
    return pos;
}

static bool parseBool(const char* valueStart, bool defaultVal) {
    if (!valueStart) return defaultVal;
    if (strncmp(valueStart, "true", 4) == 0) return true;
    if (strncmp(valueStart, "false", 5) == 0) return false;
    return defaultVal;
}

static double parseDouble(const char* valueStart, double defaultVal) {
    if (!valueStart) return defaultVal;
    char* end = nullptr;
    double val = strtod(valueStart, &end);
    if (end == valueStart) return defaultVal;
    return val;
}

static std::string parseString(const char* valueStart) {
    if (!valueStart) return "";
    if (strncmp(valueStart, "null", 4) == 0) return "";
    if (*valueStart != '"') return "";
    const char* start = valueStart + 1;
    const char* end = strchr(start, '"');
    if (!end) return "";
    return std::string(start, end - start);
}

static std::vector<std::string> parseStringArray(const char* valueStart) {
    std::vector<std::string> result;
    if (!valueStart) return result;
    if (*valueStart != '[') return result;
    const char* pos = valueStart + 1;
    while (*pos) {
        while (*pos && (*pos == ' ' || *pos == '\t' || *pos == '\n' || *pos == '\r' || *pos == ',')) pos++;
        if (*pos == ']') break;
        if (*pos == '"') {
            const char* strStart = pos + 1;
            const char* strEnd = strchr(strStart, '"');
            if (!strEnd) break;
            result.emplace_back(strStart, strEnd - strStart);
            pos = strEnd + 1;
        } else {
            pos++;
        }
    }
    return result;
}

Config loadConfig(const char* path) {
    Config config = {};
    config.equalizerEnabled = true;
    config.detectionThreshold = 1.1;
    config.referenceProfile.mean = 0.0;
    config.referenceProfile.stddev = 0.0;
    config.hasProfile = false;

    FILE* file = fopen(path, "r");
    if (!file) {
        LOGW("loadConfig: failed to open %s, using defaults", path);
        return config;
    }

    fseek(file, 0, SEEK_END);
    long fileSize = ftell(file);
    fseek(file, 0, SEEK_SET);

    if (fileSize <= 0 || fileSize > 65536) {
        fclose(file);
        return config;
    }

    std::vector<char> buffer(fileSize + 1, '\0');
    size_t bytesRead = fread(buffer.data(), 1, fileSize, file);
    fclose(file);
    if (bytesRead == 0) return config;
    buffer[bytesRead] = '\0';
    const char* json = buffer.data();

    const char* eqVal = findJsonValue(json, "latencyEqualizerEnabled");
    config.equalizerEnabled = parseBool(eqVal, true);

    const char* threshVal = findJsonValue(json, "detectionThreshold");
    config.detectionThreshold = parseDouble(threshVal, 1.1);

    const char* profileVal = findJsonValue(json, "referenceProfile");
    if (profileVal && strncmp(profileVal, "null", 4) != 0) {
        config.hasProfile = true;
        config.referenceProfile.mean = parseDouble(findJsonValue(profileVal, "mean"), 0.0);
        config.referenceProfile.stddev = parseDouble(findJsonValue(profileVal, "stddev"), 0.0);
    }

    config.activeKeyboxId = parseString(findJsonValue(json, "activeKeyboxId"));
    config.targetList = parseStringArray(findJsonValue(json, "targetList"));

    LOGI("loadConfig: equalizerEnabled=%d, threshold=%.2f, targets=%zu",
         config.equalizerEnabled, config.detectionThreshold, config.targetList.size());
    return config;
}

bool isTargetProcess(const char* packageName, const Config& config) {
    if (!packageName) return false;
    for (const auto& target : config.targetList) {
        if (target == packageName) return true;
    }
    return false;
}

} // namespace teesimplus

// ============================================================================
// Zygisk Module Implementation
// ============================================================================

class TEESimPlusModule : public zygisk::ModuleBase {
public:
    void onLoad(zygisk::Api *api, JNIEnv *env) override {
        api_ = api;
        env_ = env;
        config_ = loadConfig(CONFIG_PATH);
        LOGI("TEESimulatorPlus Zygisk module loaded");
    }

    void preAppSpecialize(zygisk::AppSpecializeArgs *args) override {
        const char* packageName = env_->GetStringUTFChars(args->nice_name, nullptr);
        if (!packageName) {
            api_->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
            return;
        }

        packageName_ = packageName;
        env_->ReleaseStringUTFChars(args->nice_name, packageName);

        if (isTargetProcess(packageName_.c_str(), config_)) {
            LOGI("Target process: %s", packageName_.c_str());
            isTarget_ = true;
        } else {
            api_->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
        }
    }

    void postAppSpecialize([[maybe_unused]] const zygisk::AppSpecializeArgs *args) override {
        if (isTarget_) {
            LOGI("Registering hooks for %s", packageName_.c_str());
            hooks::registerHooks(config_);
        }
    }

private:
    zygisk::Api *api_ = nullptr;
    JNIEnv *env_ = nullptr;
    Config config_;
    std::string packageName_;
    bool isTarget_ = false;
};

REGISTER_ZYGISK_MODULE(TEESimPlusModule)
