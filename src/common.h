#include <node.h>
#include <uv.h>
#include <v8.h>

using namespace v8;

void PlatformInit();
void PlatformThread();
int PlatformWatch(const char* path);
void PlatformUnwatch(int handle);
bool PlatformIsHandleValid(int handle);

enum EVENT_TYPE {
  EVENT_CHANGE,
  EVENT_RENAME,
  EVENT_DELETE
};

void WaitForMainThread();
void WakeupNewThread();
void PostEvent(EVENT_TYPE type, int handle, const char* path);

void CommonInit();
Handle<Value> SetCallback(const Arguments& args);
Handle<Value> Watch(const Arguments& args);
Handle<Value> Unwatch(const Arguments& args);
