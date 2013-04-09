#include "common.h"

#include <string>

static uv_async_t g_async;
static uv_sem_t g_semaphore;
static uv_thread_t g_thread;

static EVENT_TYPE g_type;
static int g_handle;
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
      case CHANGE:
        type = String::New("change");
        break;
      case DELETE:
        type = String::New("delete");
        break;
      case RENAME:
        type = String::New("rename");
        break;
    }

    Handle<Value> argv[] = {
      type, Integer::New(g_handle), String::New(g_path.c_str())
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

void PostEvent(EVENT_TYPE type, int handle, const char* path) {
  g_type = type;
  g_handle = handle;
  g_path = path;
  uv_async_send(&g_async);
}

Handle<Value> SetCallback(const Arguments& args) {
  if (!args[0]->IsFunction())
    return ThrowException(Exception::Error(String::New("Function required")));

  g_callback = Persistent<Function>::New(Handle<Function>::Cast(args[0]));

  return Undefined();
}

Handle<Value> Watch(const Arguments& args) {
  HandleScope scope;

  if (!args[0]->IsString())
    return ThrowException(Exception::Error(String::New("String required")));

  Handle<String> path = args[0]->ToString();
  int handle = PlatformWatch(*String::Utf8Value(path));
  if (!PlatformIsHandleValid(handle))
    return ThrowException(Exception::Error(String::New("Unable to watch path")));

  return scope.Close(Integer::New(handle));
}

Handle<Value> Unwatch(const Arguments& args) {
  HandleScope scope;

  if (!args[0]->IsNumber())
    return ThrowException(Exception::Error(String::New("Handle type required")));

  PlatformUnwatch(args[0]->Int32Value());
  return Undefined();
}
