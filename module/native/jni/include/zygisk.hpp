// Zygisk API header — Minimal subset for TEE Simulator Plus
// Based on https://github.com/topjohnwu/zygisk-module-sample
// Full header: https://github.com/topjohnwu/Magisk/blob/master/native/src/external/include/zygisk/api.hpp

#pragma once

#include <jni.h>

#define ZYGISK_API_VERSION 4

namespace zygisk {

struct Api;
struct AppSpecializeArgs;
struct ServerSpecializeArgs;

class ModuleBase {
public:
    virtual void onLoad([[maybe_unused]] Api *api, [[maybe_unused]] JNIEnv *env) {}
    virtual void preAppSpecialize([[maybe_unused]] AppSpecializeArgs *args) {}
    virtual void postAppSpecialize([[maybe_unused]] const AppSpecializeArgs *args) {}
    virtual void preServerSpecialize([[maybe_unused]] ServerSpecializeArgs *args) {}
    virtual void postServerSpecialize([[maybe_unused]] const ServerSpecializeArgs *args) {}
    virtual ~ModuleBase() = default;
};

struct AppSpecializeArgs {
    jint &uid;
    jint &gid;
    jintArray &gids;
    jint &runtime_flags;
    jint &mount_external;
    jstring &se_info;
    jstring &nice_name;
    jstring &instruction_set;
    jstring &app_data_dir;

    jintArray &fds_to_ignore;
    jboolean &is_child_zygote;
    jboolean &is_top_app;
    jobjectArray &pkg_data_info_list;
    jobjectArray &whitelisted_data_info_list;
    jboolean &mount_data_dirs;
    jboolean &mount_storage_dirs;
};

struct ServerSpecializeArgs {
    jint &uid;
    jint &gid;
    jintArray &gids;
    jint &runtime_flags;
    jlong &permitted_capabilities;
    jlong &effective_capabilities;
};

enum Option : int {
    FORCE_DENYLIST_UNMOUNT = 0,
    DLCLOSE_MODULE_LIBRARY = 1,
};

struct Api {
    void setOption(Option opt);
    int getFlags();
    int connectCompanion();
    void pltHookRegister(const char *regex, const char *symbol, void *newFunc, void **oldFunc);
    void pltHookExclude(const char *regex, const char *symbol);
    bool pltHookCommit();
};

} // namespace zygisk

#define REGISTER_ZYGISK_MODULE(clazz) \
void *_zygisk_module_entry = nullptr; \
extern "C" [[gnu::visibility("default")]] void zygisk_module_entry( \
    zygisk::Api *api, JNIEnv *env) { \
    static clazz module; \
    module.onLoad(api, env); \
    _zygisk_module_entry = &module; \
} \
extern "C" [[gnu::visibility("default")]] int zygisk_companion_entry(int fd) { \
    (void)fd; return 0; \
}
