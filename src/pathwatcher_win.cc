#include "common.h"

void PlatformInit() {
}

void PlatformThread() {
}

WatcherHandle PlatformWatch(const char* path) {
  return 0;
}

void PlatformUnwatch(WatcherHandle handle) {
}

bool PlatformIsHandleValid(WatcherHandle handle) {
  return true;
}
