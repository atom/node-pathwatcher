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
  NanScope();

  if (!g_callback.IsEmpty()) {
    Handle<String> type;
    switch (g_type) {
      case EVENT_CHANGE:
        type = NanNew("change");
        break;
      case EVENT_DELETE:
        type = NanNew("delete");
        break;
      case EVENT_RENAME:
        type = NanNew("rename");
        break;
      case EVENT_CHILD_CREATE:
        type = NanNew("child-create");
        break;
      case EVENT_CHILD_CHANGE:
        type = NanNew("child-change");
        break;
      case EVENT_CHILD_DELETE:
        type = NanNew("child-delete");
        break;
      case EVENT_CHILD_RENAME:
        type = NanNew("child-rename");
        break;
      default:
        type = NanNew("unknown");
        return;
    }

    Handle<Value> argv[] = {
        type,
        WatcherHandleToV8Value(g_handle),
        NanNew(g_new_path.data(), g_new_path.size()),
        NanNew(g_old_path.data(), g_old_path.size()),
    };
    NanNew(g_callback)->Call(NanGetCurrentContext()->Global(), 4, argv);
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
  NanScope();

  if (!args[0]->IsFunction())
    return NanThrowTypeError("Function required");

  NanAssignPersistent(g_callback, Local<Function>::Cast(args[0]));
  NanReturnUndefined();
}

NAN_METHOD(Watch) {
  NanScope();

  if (!args[0]->IsString())
    return NanThrowTypeError("String required");

  Handle<String> path = args[0]->ToString();
  WatcherHandle handle = PlatformWatch(*String::Utf8Value(path));
  if (!PlatformIsHandleValid(handle)) {
    int error_number = PlatformInvalidHandleToErrorNumber(handle);
    v8::Local<v8::Value> err =
      v8::Exception::Error(NanNew<v8::String>("Unable to watch path"));
    v8::Local<v8::Object> err_obj = err.As<v8::Object>();
    if (error_number != 0) {
      err_obj->Set(NanNew<v8::String>("errno"),
                   NanNew<v8::Integer>(error_number));
#if NODE_VERSION_AT_LEAST(0, 11, 5)
      // Node 0.11.5 is the first version to contain libuv v0.11.6, which
      // contains https://github.com/libuv/libuv/commit/3ee4d3f183 which changes
      // uv_err_name from taking a struct uv_err_t (whose uv_err_code `code` is
      // a difficult-to-produce uv-specific errno) to just take an int which is
      // a negative errno.
      err_obj->Set(NanNew<v8::String>("code"),
                   NanNew<v8::String>(uv_err_name(-error_number)));
#endif
    }
    return NanThrowError(err);
  }

  if (g_watch_count++ == 0) {
    SetRef(true);
  }

  NanReturnValue(WatcherHandleToV8Value(handle));
}

NAN_METHOD(Unwatch) {
  NanScope();

  if (!IsV8ValueWatcherHandle(args[0]))
    return NanThrowTypeError("Handle type required");

  PlatformUnwatch(V8ValueToWatcherHandle(args[0]));

  if (--g_watch_count == 0) {
    SetRef(false);
  }

  NanReturnUndefined();
}
