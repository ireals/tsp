// Zygisk API stub implementations
// These weak symbols are overridden at runtime by the Zygisk framework.
// They exist only to satisfy the linker during build.

#include "include/zygisk.hpp"

namespace zygisk {

__attribute__((weak))
void Api::setOption([[maybe_unused]] Option opt) {}

__attribute__((weak))
int Api::getFlags() { return 0; }

__attribute__((weak))
int Api::connectCompanion() { return -1; }

__attribute__((weak))
void Api::pltHookRegister([[maybe_unused]] const char *regex,
                          [[maybe_unused]] const char *symbol,
                          [[maybe_unused]] void *newFunc,
                          [[maybe_unused]] void **oldFunc) {}

__attribute__((weak))
void Api::pltHookExclude([[maybe_unused]] const char *regex,
                         [[maybe_unused]] const char *symbol) {}

__attribute__((weak))
bool Api::pltHookCommit() { return false; }

} // namespace zygisk
