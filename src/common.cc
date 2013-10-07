#include "common.h"

#include "node_internals.h"

#include <string>

static uv_async_t g_async;
static uv_sem_t g_semaphore;
static uv_thread_t g_thread;

static EVENT_TYPE g_type;
static WatcherHandle g_handle;
static std::string g_path;
static Persistent<Function> g_callback;

static void CommonThread(void* handle) {
  WaitForMainThread();
  PlatformThread();
}

static void MakeCallbackInMainThread(uv_async_t* handle, int status) {
  HandleScope scope;

  if (!g_callback.IsEmpty()) {
    Handle<String> type;
    switch (g_type) {
      case EVENT_CHANGE:
        type = String::New("change");
        break;
      case EVENT_DELETE:
        type = String::New("delete");
        break;
      case EVENT_RENAME:
        type = String::New("rename");
        break;
    }

    Handle<Value> argv[] = {
      type, WatcherHandleToV8Value(g_handle), String::New(g_path.c_str())
    };
    g_callback->Call(Context::GetCurrent()->Global(), 3, argv);
  }

  WakeupNewThread();
}

void CommonInit() {
  uv_sem_init(&g_semaphore, 0);
  uv_async_init(uv_default_loop(), &g_async, MakeCallbackInMainThread);
  uv_thread_create(&g_thread, &CommonThread, NULL);
}

void WaitForMainThread() {
  uv_sem_wait(&g_semaphore);
}

void WakeupNewThread() {
  uv_sem_post(&g_semaphore);
}

void PostEvent(EVENT_TYPE type, WatcherHandle handle, const char* path) {
  g_type = type;
  g_handle = handle;
  g_path = path;
  uv_async_send(&g_async);
}

Handle<Value> SetCallback(const Arguments& args) {
  if (!args[0]->IsFunction())
    return node::ThrowTypeError("Function required");

  g_callback = Persistent<Function>::New(Handle<Function>::Cast(args[0]));

  return Undefined();
}

Handle<Value> Watch(const Arguments& args) {
  HandleScope scope;

  if (!args[0]->IsString())
    return node::ThrowTypeError("String required");

  Handle<String> path = args[0]->ToString();
  WatcherHandle handle = PlatformWatch(*String::Utf8Value(path));
  if (!PlatformIsHandleValid(handle))
    return node::ThrowError("Unable to watch path");

  return scope.Close(WatcherHandleToV8Value(handle));
}

Handle<Value> Unwatch(const Arguments& args) {
  HandleScope scope;

  if (!IsV8ValueWatcherHandle(args[0]))
    return node::ThrowTypeError("Handle type required");

  PlatformUnwatch(V8ValueToWatcherHandle(args[0]));
  return Undefined();
}
