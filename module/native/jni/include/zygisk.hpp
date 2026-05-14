// Zygisk API header — Minimal subset for TEE Simulator Plus
// Based on https://github.com/topjohnwu/zygisk-module-sample
//
// The Zygisk framework dynamically resolves these symbols at runtime.
// We provide weak stub implementations so the module links without errors.

#pragma once

#include <jni.h>

#define ZYGISK_API_VERSION 4

namespace zygisk {

struct AppSpecializeArgs;
struct ServerSpecializeArgs;

enum Option : int {
    FORCE_DENYLIST_UNMOUNT = 0,
    DLCLOSE_MODULE_LIBRARY = 1,
};

struct Api {
    // These are implemented as weak symbols — the Zygisk framework
    // overrides them at runtime when loading the module.
    void setOption(Option opt);
    int getFlags();
    int connectCompanion();
    void pltHookRegister(const char *regex, const char *symbol, void *newFunc, void **oldFunc);
    void pltHookExclude(const char *regex, const char *symbol);
    bool pltHookCommit();
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

class ModuleBase {
public:
    virtual void onLoad([[maybe_unused]] Api *api, [[maybe_unused]] JNIEnv *env) {}
    virtual void preAppSpecialize([[maybe_unused]] AppSpecializeArgs *args) {}
    virtual void postAppSpecialize([[maybe_unused]] const AppSpecializeArgs *args) {}
    virtual void preServerSpecialize([[maybe_unused]] ServerSpecializeArgs *args) {}
    virtual void postServerSpecialize([[maybe_unused]] const ServerSpecializeArgs *args) {}
    virtual ~ModuleBase() = default;
};

} // namespace zygisk

// Macro to register a Zygisk module class.
// The Zygisk framework looks for these exported symbols when loading the .so.
#define REGISTER_ZYGISK_MODULE(clazz) \
extern "C" [[gnu::visibility("default")]] void zygisk_module_entry( \
    zygisk::Api *api, JNIEnv *env) { \
    static clazz module; \
    module.onLoad(api, env); \
} \
extern "C" [[gnu::visibility("default")]] int zygisk_companion_entry( \
    [[maybe_unused]] int fd) { \
    return 0; \
}
