#ifndef SRC_COMMON_H_
#define SRC_COMMON_H_

#include <node.h>
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
typedef int WatcherHandle;
#define WatcherHandleToV8Value(h) Integer::New(h)
#define V8ValueToWatcherHandle(v) v->IntegerValue()
#define IsV8ValueWatcherHandle(v) v->IsNumber()
#endif

void PlatformInit();
void PlatformThread();
WatcherHandle PlatformWatch(const char* path);
void PlatformUnwatch(WatcherHandle handle);
bool PlatformIsHandleValid(WatcherHandle handle);

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
                      const char* new_path = "",
                      const char* old_path = "");

void CommonInit();
Handle<Value> SetCallback(const Arguments& args);
Handle<Value> Watch(const Arguments& args);
Handle<Value> Unwatch(const Arguments& args);

#endif  // SRC_COMMON_H_
