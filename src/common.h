#ifndef SRC_COMMON_H_
#define SRC_COMMON_H_

#include <vector>

#include "nan.h"
using namespace v8;

#ifdef _WIN32
// Platform-dependent definetion of handle.
typedef HANDLE WatcherHandle;

// Conversion between V8 value and WatcherHandle.
Handle<Value> WatcherHandleToV8Value(WatcherHandle handle);
WatcherHandle V8ValueToWatcherHandle(Handle<Value> value);
bool IsV8ValueWatcherHandle(Handle<Value> value);
#else
// Correspoding definetions on OS X and Linux.
typedef int32_t WatcherHandle;
#define WatcherHandleToV8Value(h) Nan::New<Integer>(h)
#define V8ValueToWatcherHandle(v) v->Int32Value()
#define IsV8ValueWatcherHandle(v) v->IsInt32()
#endif

void PlatformInit();
void PlatformThread();
WatcherHandle PlatformWatch(const char* path);
void PlatformUnwatch(WatcherHandle handle);
bool PlatformIsHandleValid(WatcherHandle handle);
int PlatformInvalidHandleToErrorNumber(WatcherHandle handle);

enum EVENT_TYPE {
  EVENT_NONE,
  EVENT_CHANGE,
  EVENT_RENAME,
  EVENT_DELETE,
  EVENT_CHILD_CHANGE,
  EVENT_CHILD_RENAME,
  EVENT_CHILD_DELETE,
  EVENT_CHILD_CREATE,
};

void WaitForMainThread();
void WakeupNewThread();
void PostEventAndWait(EVENT_TYPE type,
                      WatcherHandle handle,
                      const std::vector<char>& new_path,
                      const std::vector<char>& old_path = std::vector<char>());

void CommonInit();

NAN_METHOD(SetCallback);
NAN_METHOD(Watch);
NAN_METHOD(Unwatch);

#endif  // SRC_COMMON_H_
