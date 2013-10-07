#include "common.h"

void PlatformInit() {
}

void PlatformThread() {
}

int PlatformWatch(const char* path) {
  return 0;
}

void PlatformUnwatch(int fd) {
}

bool PlatformIsHandleValid(int handle) {
  return true;
}
