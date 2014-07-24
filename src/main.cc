#include "common.h"
#include "handle_map.h"

namespace {

void Init(Handle<Object> exports) {
  CommonInit();
  PlatformInit();

  NODE_SET_METHOD(exports, "setCallback", SetCallback);
  NODE_SET_METHOD(exports, "watch", Watch);
  NODE_SET_METHOD(exports, "unwatch", Unwatch);

  HandleMap::Initialize(exports);
}

}  // namespace

NODE_MODULE(pathwatcher, Init)
