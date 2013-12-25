#include "common.h"
#include "handle_map.h"

void Init(Handle<Object> exports) {
  CommonInit();
  PlatformInit();

  NODE_SET_METHOD(exports, "setCallback", SetCallback);
  NODE_SET_METHOD(exports, "watch", Watch);
  NODE_SET_METHOD(exports, "unwatch", Unwatch);

  HandleMap::Initialize(exports);
}

NODE_MODULE(pathwatcher, Init)
