#include <node.h>
#include <uv.h>
#include <v8.h>

using namespace v8;

#ifdef _WIN32
#include <windows.h>
typedef HANDLE WatcherHandle;
#else
typedef int WatcherHandle;
#endif


void PlatformInit();
void PlatformThread();
WatcherHandle PlatformWatch(const char* path);
void PlatformUnwatch(WatcherHandle handle);
bool PlatformIsHandleValid(WatcherHandle handle);

enum EVENT_TYPE {
  EVENT_CHANGE,
  EVENT_RENAME,
  EVENT_DELETE
};

void WaitForMainThread();
void WakeupNewThread();
void PostEvent(EVENT_TYPE type, WatcherHandle handle, const char* path);

void CommonInit();
Handle<Value> SetCallback(const Arguments& args);
Handle<Value> Watch(const Arguments& args);
Handle<Value> Unwatch(const Arguments& args);
