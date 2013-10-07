#include "common.h"

// Object template to create representation of WatcherHandle.
Persistent<ObjectTemplate> g_object_template;

Handle<Value> WatcherHandleToV8Value(WatcherHandle handle) {
  Handle<Value> value = g_object_template->NewInstance();
  value->ToObject()->SetPointerInInternalField(0, handle);
  return value;
}

WatcherHandle V8ValueToWatcherHandle(Handle<Value> value) {
  return reinterpret_cast<WatcherHandle>(value->ToObject()->
      GetPointerFromInternalField(0));
}

bool IsV8ValueWatcherHandle(Handle<Value> value) {
  return value->IsObject() && value->ToObject()->InternalFieldCount() == 1;
}

void PlatformInit() {
  g_object_template = Persistent<ObjectTemplate>::New(ObjectTemplate::New());
  g_object_template->SetInternalFieldCount(1);

  WakeupNewThread();
}

void PlatformThread() {
}

WatcherHandle PlatformWatch(const char* path) {
  return 0;
}

void PlatformUnwatch(WatcherHandle handle) {
}

bool PlatformIsHandleValid(WatcherHandle handle) {
  return handle != INVALID_HANDLE_VALUE;
}
