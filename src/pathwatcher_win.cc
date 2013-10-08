#include <map>
#include <memory>
#include <vector>

#include "common.h"

#include <Shlwapi.h>  // NOLINT

// Size of the buffer to store result of ReadDirectoryChangesW.
static const unsigned int kDirectoryWatcherBufferSize = 4096;

// Object template to create representation of WatcherHandle.
Persistent<ObjectTemplate> g_object_template;

// Mutex for the HandleWrapper map.
uv_mutex_t g_handle_wrap_map_mutex;

// The global IOCP to be quested.
static HANDLE g_iocp;

struct HandleWrapper {
  HandleWrapper(WatcherHandle handle, const char* path)
      : dir_handle(handle),
        path(path) {
    map_[dir_handle] = this;
    memset(&overlapped, 0, sizeof(overlapped));
  }

  ~HandleWrapper() {
    map_.erase(dir_handle);
  }

  WatcherHandle dir_handle;
  OVERLAPPED overlapped;
  std::string path;
  char buffer[kDirectoryWatcherBufferSize];

  static HandleWrapper* Get(WatcherHandle key) { return map_[key]; }

  static std::map<WatcherHandle, HandleWrapper*> map_;
};

std::map<WatcherHandle, HandleWrapper*> HandleWrapper::map_;

struct WatcherEvent {
  EVENT_TYPE type;
  WatcherHandle handle;
  std::string new_path;
  std::string old_path;
};

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
  uv_mutex_init(&g_handle_wrap_map_mutex);

  g_iocp = CreateIoCompletionPort(INVALID_HANDLE_VALUE, NULL, NULL, 0);

  g_object_template = Persistent<ObjectTemplate>::New(ObjectTemplate::New());
  g_object_template->SetInternalFieldCount(1);

  WakeupNewThread();
}

void PlatformThread() {
  DWORD bytes;
  ULONG_PTR key;
  OVERLAPPED* overlapped;

  while (true) {
    GetQueuedCompletionStatus(g_iocp, &bytes, &key, &overlapped, 0);
    if (overlapped && overlapped->InternalHigh > 0) {
      std::string old_path;
      std::vector<WatcherEvent> events;

      uv_mutex_lock(&g_handle_wrap_map_mutex);
      HandleWrapper* handle = reinterpret_cast<HandleWrapper*>(key);
      if (!handle) {
        uv_mutex_unlock(&g_handle_wrap_map_mutex);
        return;
      }

      DWORD offset = 0;
      do {
        FILE_NOTIFY_INFORMATION* file_info =
            reinterpret_cast<FILE_NOTIFY_INFORMATION*>(handle->buffer + offset);

        // Emit events for children.
        EVENT_TYPE event = EVENT_NONE;
        switch (file_info->Action) {
          case FILE_ACTION_ADDED:
            event = EVENT_CHILD_CREATE;
            break;
          case FILE_ACTION_REMOVED:
            event = EVENT_CHILD_DELETE;
            break;
          case FILE_ACTION_RENAMED_OLD_NAME:
            event = EVENT_CHILD_RENAME;
            break;
          case FILE_ACTION_RENAMED_NEW_NAME:
            event = EVENT_CHILD_RENAME;
            break;
          case FILE_ACTION_MODIFIED:
            event = EVENT_CHILD_CHANGE;
            break;
        }

        if (event != EVENT_NONE) {
          // The FileNameLength is in "bytes", but the WideCharToMultiByte
          // requires the length to be in "characters"!
          int file_name_length_in_characters =
              file_info->FileNameLength / sizeof(wchar_t);

          char filename[MAX_PATH + 1] = { 0 };
          int size = WideCharToMultiByte(CP_UTF8,
                                         0,
                                         file_info->FileName,
                                         file_name_length_in_characters,
                                         filename,
                                         MAX_PATH,
                                         NULL,
                                         NULL);

          // Convert filename to normalized path.
          std::string cat_path = handle->path + '\\' + filename;
          char path[MAX_PATH + 1] = { 0 };
          PathCanonicalize(path, cat_path.c_str());

          if (file_info->Action == FILE_ACTION_RENAMED_OLD_NAME) {
            // Do not send rename event until the NEW_NAME event, but still keep
            // a record of old name.
            old_path = path;
          } else if (file_info->Action == FILE_ACTION_RENAMED_NEW_NAME) {
            WatcherEvent e = { event, handle->dir_handle, path, old_path };
            events.push_back(e);
            old_path.clear();
          } else {
            WatcherEvent e = { event, handle->dir_handle, path };
            events.push_back(e);
          }
        }

        offset = file_info->NextEntryOffset;
      } while (offset);
      uv_mutex_unlock(&g_handle_wrap_map_mutex);

      for (int i = 0; i < events.size(); ++i)
        PostEventAndWait(events[i].type,
                         events[i].handle,
                         events[i].new_path,
                         events[i].old_path);
    }
  }
}

WatcherHandle PlatformWatch(const char* path) {
  wchar_t wpath[MAX_PATH + 1];
  MultiByteToWideChar(CP_UTF8, 0, path, -1, wpath, MAX_PATH);

  // Requires a directory, file watching is emulated in js.
  DWORD attr = GetFileAttributesW(wpath);
  if (attr == INVALID_FILE_ATTRIBUTES || !(attr & FILE_ATTRIBUTE_DIRECTORY)) {
    fprintf(stderr, "%s is not a directory\n", path);
    return INVALID_HANDLE_VALUE;
  }

  WatcherHandle handle = CreateFileW(wpath,
                                     FILE_LIST_DIRECTORY,
                                     FILE_SHARE_READ | FILE_SHARE_DELETE |
                                       FILE_SHARE_WRITE,
                                     NULL,
                                     OPEN_EXISTING,
                                     FILE_FLAG_BACKUP_SEMANTICS |
                                       FILE_FLAG_OVERLAPPED,
                                     NULL);
  if (!PlatformIsHandleValid(handle)) {
    fprintf(stderr, "Unable to call CreateFileW for %s\n", path);
    return INVALID_HANDLE_VALUE;
  }

  uv_mutex_lock(&g_handle_wrap_map_mutex);
  std::unique_ptr<HandleWrapper> handle_wrapper(
      new HandleWrapper(handle, path));
  uv_mutex_unlock(&g_handle_wrap_map_mutex);

  if (CreateIoCompletionPort(handle_wrapper->dir_handle,
                             g_iocp,
                             reinterpret_cast<ULONG_PTR>(handle_wrapper.get()),
                             0) == NULL) {
    fprintf(stderr, "CreateIoCompletionPort failed\n");
    return INVALID_HANDLE_VALUE;
  }

  if (!ReadDirectoryChangesW(handle_wrapper->dir_handle,
                             handle_wrapper->buffer,
                             kDirectoryWatcherBufferSize,
                             FALSE,
                             FILE_NOTIFY_CHANGE_FILE_NAME      |
                               FILE_NOTIFY_CHANGE_DIR_NAME     |
                               FILE_NOTIFY_CHANGE_ATTRIBUTES   |
                               FILE_NOTIFY_CHANGE_SIZE         |
                               FILE_NOTIFY_CHANGE_LAST_WRITE   |
                               FILE_NOTIFY_CHANGE_LAST_ACCESS  |
                               FILE_NOTIFY_CHANGE_CREATION     |
                               FILE_NOTIFY_CHANGE_SECURITY,
                             NULL,
                             &handle_wrapper->overlapped,
                             NULL)) {
    fprintf(stderr, "ReadDirectoryChangesW failed\n");
    return INVALID_HANDLE_VALUE;
  }

  // The pointer is leaked if no error happened.
  return handle_wrapper.release()->dir_handle;
}

void PlatformUnwatch(WatcherHandle handle) {
  if (PlatformIsHandleValid(handle)) {
    uv_mutex_lock(&g_handle_wrap_map_mutex);
    CloseHandle(handle);
    delete HandleWrapper::Get(handle);
    uv_mutex_unlock(&g_handle_wrap_map_mutex);
  }
}

bool PlatformIsHandleValid(WatcherHandle handle) {
  return handle != INVALID_HANDLE_VALUE;
}
