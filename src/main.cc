#include "common.h"
#include "handle_map.h"

namespace {

void Init(Local<Object> exports) {
  CommonInit();
  PlatformInit();

  Nan::SetMethod(exports, "setCallback", SetCallback);
  Nan::SetMethod(exports, "watch", Watch);
  Nan::SetMethod(exports, "unwatch", Unwatch);

  HandleMap::Initialize(exports);
}

}  // namespace

NODE_MODULE(pathwatcher, Init)
