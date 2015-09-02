#include "common.h"

static uv_async_t g_async;
static int g_watch_count;
static uv_sem_t g_semaphore;
static uv_thread_t g_thread;

static EVENT_TYPE g_type;
static WatcherHandle g_handle;
static std::vector<char> g_new_path;
static std::vector<char> g_old_path;
static Persistent<Function> g_callback;

static void CommonThread(void* handle) {
  WaitForMainThread();
  PlatformThread();
}

#if NODE_VERSION_AT_LEAST(0, 11, 13)
static void MakeCallbackInMainThread(uv_async_t* handle) {
#else
static void MakeCallbackInMainThread(uv_async_t* handle, int status) {
#endif
  Nan::HandleScope scope;

  if (!g_callback.IsEmpty()) {
    Handle<String> type;
    switch (g_type) {
      case EVENT_CHANGE:
        type = Nan::New("change").ToLocalChecked();
        break;
      case EVENT_DELETE:
        type = Nan::New("delete").ToLocalChecked();
        break;
      case EVENT_RENAME:
        type = Nan::New("rename").ToLocalChecked();
        break;
      case EVENT_CHILD_CREATE:
        type = Nan::New("child-create").ToLocalChecked();
        break;
      case EVENT_CHILD_CHANGE:
        type = Nan::New("child-change").ToLocalChecked();
        break;
      case EVENT_CHILD_DELETE:
        type = Nan::New("child-delete").ToLocalChecked();
        break;
      case EVENT_CHILD_RENAME:
        type = Nan::New("child-rename").ToLocalChecked();
        break;
      default:
        type = Nan::New("unknown").ToLocalChecked();
        return;
    }

    Handle<Value> argv[] = {
        type,
        WatcherHandleToV8Value(g_handle),
        Nan::New(g_new_path.data(), g_new_path.size()),
        Nan::New(g_old_path.data(), g_old_path.size()),
    };
    Nan::New(g_callback)->Call(Nan::GetCurrentContext()->Global(), 4, argv);
  }

  WakeupNewThread();
}

static void SetRef(bool value) {
  uv_handle_t* h = reinterpret_cast<uv_handle_t*>(&g_async);
  if (value) {
    uv_ref(h);
  } else {
    uv_unref(h);
  }
}

void CommonInit() {
  uv_sem_init(&g_semaphore, 0);
  uv_async_init(uv_default_loop(), &g_async, MakeCallbackInMainThread);
  // As long as any uv_ref'd uv_async_t handle remains active, the node
  // process will never exit, so we must call uv_unref here (#47).
  SetRef(false);
  g_watch_count = 0;
  uv_thread_create(&g_thread, &CommonThread, NULL);
}

void WaitForMainThread() {
  uv_sem_wait(&g_semaphore);
}

void WakeupNewThread() {
  uv_sem_post(&g_semaphore);
}

void PostEventAndWait(EVENT_TYPE type,
                      WatcherHandle handle,
                      const std::vector<char>& new_path,
                      const std::vector<char>& old_path) {
  // FIXME should not pass args by settings globals.
  g_type = type;
  g_handle = handle;
  g_new_path = new_path;
  g_old_path = old_path;

  uv_async_send(&g_async);
  WaitForMainThread();
}

NAN_METHOD(SetCallback) {
  Nan::HandleScope scope;

  if (!info[0]->IsFunction())
    return Nan::ThrowTypeError("Function required");

  g_callback.Reset( Local<Function>::Cast(info[0]));
  return;
}

NAN_METHOD(Watch) {
  Nan::HandleScope scope;

  if (!info[0]->IsString())
    return Nan::ThrowTypeError("String required");

  Handle<String> path = info[0]->ToString();
  WatcherHandle handle = PlatformWatch(*String::Utf8Value(path));
  if (!PlatformIsHandleValid(handle)) {
    int error_number = PlatformInvalidHandleToErrorNumber(handle);
    v8::Local<v8::Value> err =
      v8::Exception::Error(Nan::New<v8::String>("Unable to watch path").ToLocalChecked());
    v8::Local<v8::Object> err_obj = err.As<v8::Object>();
    if (error_number != 0) {
      err_obj->Set(Nan::New<v8::String>("errno").ToLocalChecked(),
                   Nan::New<v8::Integer>(error_number));
#if NODE_VERSION_AT_LEAST(0, 11, 5)
      // Node 0.11.5 is the first version to contain libuv v0.11.6, which
      // contains https://github.com/libuv/libuv/commit/3ee4d3f183 which changes
      // uv_err_name from taking a struct uv_err_t (whose uv_err_code `code` is
      // a difficult-to-produce uv-specific errno) to just take an int which is
      // a negative errno.
      err_obj->Set(Nan::New<v8::String>("code").ToLocalChecked(),
                   Nan::New<v8::String>(uv_err_name(-error_number))).ToLocalChecked();
#endif
    }
    return Nan::ThrowError(err);
  }

  if (g_watch_count++ == 0)
    SetRef(true);

  info.GetReturnValue().Set(WatcherHandleToV8Value(handle));
}

NAN_METHOD(Unwatch) {
  Nan::HandleScope scope;

  if (!IsV8ValueWatcherHandle(info[0]))
    return Nan::ThrowTypeError("Handle type required");

  PlatformUnwatch(V8ValueToWatcherHandle(info[0]));

  if (--g_watch_count == 0)
    SetRef(false);

  return;
}
