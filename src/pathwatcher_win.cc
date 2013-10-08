#include "common.h"

#include <map>
#include <memory>
#include <string>
#include <vector>

#include <Shlwapi.h>

// Size of the buffer to store result of ReadDirectoryChangesW.
static const unsigned int uv_directory_watcher_buffer_size = 4096;

// Object template to create representation of WatcherHandle.
Persistent<ObjectTemplate> g_object_template;

// HandleWrapper that need to be deleted.
std::vector<WatcherHandle> g_gabage_handles;

// Mutex for the g_gabage_handles.
uv_mutex_t g_gabage_handles_mutex;

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
  char buffer[uv_directory_watcher_buffer_size];

  static HandleWrapper* Get(WatcherHandle key) { return map_[key]; }

  static std::map<WatcherHandle, HandleWrapper*> map_;
};

std::map<WatcherHandle, HandleWrapper*> HandleWrapper::map_;

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
  uv_mutex_init(&g_gabage_handles_mutex);
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
    if (overlapped) {
      HandleWrapper* handle = reinterpret_cast<HandleWrapper*>(key);

      std::string old_path;

      DWORD offset = 0;
      FILE_NOTIFY_INFORMATION* file_info;
      file_info = (FILE_NOTIFY_INFORMATION*)(handle->buffer + offset);

      do {
        file_info = (FILE_NOTIFY_INFORMATION*)((char*)file_info + offset);

        // Emit "change" for file creation and deletion.
        switch (file_info->Action) {
          case FILE_ACTION_ADDED:
          case FILE_ACTION_REMOVED:
          case FILE_ACTION_RENAMED_NEW_NAME:
            PostEventAndWait(EVENT_CHANGE, handle->dir_handle);
            break;
        }

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
          char filename[MAX_PATH];
          WideCharToMultiByte(CP_UTF8,
                              0,
                              file_info->FileName,
                              file_info->FileNameLength,
                              filename,
                              MAX_PATH,
                              NULL,
                              NULL);

          // Convert filename to normalized path.
          std::string cat_path = handle->path + '\\' + filename;
          char path[MAX_PATH] = { 0 };
          PathCanonicalize(path, cat_path.c_str());

          if (file_info->Action == FILE_ACTION_RENAMED_OLD_NAME)
            old_path = path;
          else if (file_info->Action == FILE_ACTION_RENAMED_NEW_NAME)
            PostEventAndWait(event, handle->dir_handle, path, old_path.c_str());
          else
            PostEventAndWait(event, handle->dir_handle, path);
        }

        offset = file_info->NextEntryOffset;
      } while(offset);
    }

    std::vector<WatcherHandle> gabage_handles;

    uv_mutex_lock(&g_gabage_handles_mutex);
    gabage_handles.swap(g_gabage_handles);
    uv_mutex_unlock(&g_gabage_handles_mutex);

    // Safely delete handles after all events are dispatched.
    uv_mutex_lock(&g_handle_wrap_map_mutex);
    for (int i = 0; i < gabage_handles.size(); ++i)
      delete HandleWrapper::Get(gabage_handles[i]);
    uv_mutex_unlock(&g_handle_wrap_map_mutex);
  }
}

WatcherHandle PlatformWatch(const char* path) {
  wchar_t wpath[MAX_PATH];
  MultiByteToWideChar(CP_UTF8, 0, path, -1, wpath, MAX_PATH);

  // Requires a directory, file watching is emulated in js.
  DWORD attr = GetFileAttributesW(wpath);
  if (attr == INVALID_FILE_ATTRIBUTES || !(attr & FILE_ATTRIBUTE_DIRECTORY))
    return INVALID_HANDLE_VALUE;

  WatcherHandle handle = CreateFileW(wpath,
                                     FILE_LIST_DIRECTORY,
                                     FILE_SHARE_READ | FILE_SHARE_DELETE |
                                       FILE_SHARE_WRITE,
                                     NULL,
                                     OPEN_EXISTING,
                                     FILE_FLAG_BACKUP_SEMANTICS |
                                       FILE_FLAG_OVERLAPPED,
                                     NULL);
  if (!PlatformIsHandleValid(handle))
    return INVALID_HANDLE_VALUE;

  uv_mutex_lock(&g_handle_wrap_map_mutex);
  std::unique_ptr<HandleWrapper> handle_wrapper(
      new HandleWrapper(handle, path));
  uv_mutex_unlock(&g_handle_wrap_map_mutex);

  if (CreateIoCompletionPort(handle_wrapper->dir_handle,
                             g_iocp,
                             reinterpret_cast<ULONG_PTR>(handle_wrapper.get()),
                             0) == NULL)
    return INVALID_HANDLE_VALUE;

  if (!ReadDirectoryChangesW(handle_wrapper->dir_handle,
                             handle_wrapper->buffer,
                             uv_directory_watcher_buffer_size,
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
                             NULL))
    return INVALID_HANDLE_VALUE;

  // The pointer is leaked if no error happened.
  return handle_wrapper.release()->dir_handle;
}

void PlatformUnwatch(WatcherHandle handle) {
  if (PlatformIsHandleValid(handle)) {
    CloseHandle(handle);

    // Add the handle to the to-be-deleted list.
    uv_mutex_lock(&g_gabage_handles_mutex);
    g_gabage_handles.push_back(handle);
    uv_mutex_unlock(&g_gabage_handles_mutex);
  }
}

bool PlatformIsHandleValid(WatcherHandle handle) {
  return handle != INVALID_HANDLE_VALUE;
}
