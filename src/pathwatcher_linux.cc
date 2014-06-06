#include <errno.h>
#include <stdio.h>

#include <sys/types.h>
#include <sys/inotify.h>
#include <linux/limits.h>
#include <unistd.h>

#include <algorithm>

#include <map>
#include <string>

#include "common.h"

static int g_inotify;

static std::map<int, std::string> handlemap;

void PlatformInit() {
  g_inotify = inotify_init();
  if (g_inotify == -1) {
    return;
  }

  WakeupNewThread();
}

void PlatformThread() {
  // Needs to be large enough for sizeof(inotify_event) + strlen(filename).
  char buf[4096];

  while (true) {
    int size;
    do {
      size = read(g_inotify, buf, sizeof(buf));
    } while (size == -1 && errno == EINTR);

    if (size == -1) {
      break;
    } else if (size == 0) {
      break;
    }

    inotify_event* e;
    for (char* p = buf; p < buf + size; p += sizeof(*e) + e->len) {
      e = reinterpret_cast<inotify_event*>(p);

      int fd = e->wd;
      EVENT_TYPE type;
      std::string fullpath = handlemap[fd];

      if (e->len > 0) {
        fullpath +=  "/";
        fullpath += e->name;
      }

      std::vector<char> path(fullpath.begin(), fullpath.end());

      // Note that inotify won't tell us where the file or directory has been
      // moved to, so we just treat IN_MOVE_SELF as file being deleted.
      if (e->mask & (IN_ATTRIB | IN_CREATE | IN_DELETE | IN_MODIFY | IN_MOVE)) {
        type = EVENT_CHANGE;
      } else if (e->mask & (IN_DELETE_SELF | IN_MOVE_SELF)) {
        type = EVENT_DELETE;
      } else {
        continue;
      }

      PostEventAndWait(type, fd, path);
    }
  }
}

WatcherHandle PlatformWatch(const char* path) {
  int fd = inotify_add_watch(g_inotify, path, IN_ATTRIB | IN_CREATE |
      IN_DELETE | IN_MODIFY | IN_MOVE | IN_MOVE_SELF | IN_DELETE_SELF);

  handlemap[fd] = std::string(path);

  return fd;
}

void PlatformUnwatch(WatcherHandle fd) {
  inotify_rm_watch(g_inotify, fd);
  handlemap.erase(fd);
}

bool PlatformIsHandleValid(WatcherHandle handle) {
  return handle >= 0;
}
