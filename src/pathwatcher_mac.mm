#include <algorithm>

#include <errno.h>
#include <unistd.h>
#include <sys/event.h>
#include <sys/param.h>
#include <sys/time.h>
#include <sys/types.h>

#include "common.h"

static int g_kqueue;
static int g_init_errno;

void PlatformInit() {
  g_kqueue = kqueue();
  if (g_kqueue == -1) {
    g_init_errno = errno;
    return;
  }

  WakeupNewThread();
}

void PlatformThread() {
  struct kevent event;

  while (true) {
    int r;
    do {
      r = kevent(g_kqueue, NULL, 0, &event, 1, NULL);
    } while ((r == -1 && errno == EINTR) || r == 0);

    EVENT_TYPE type;
    int fd = static_cast<int>(event.ident);
    std::vector<char> path;

    if (event.fflags & NOTE_WRITE) {
      type = EVENT_CHANGE;
    } else if (event.fflags & NOTE_DELETE) {
      type = EVENT_DELETE;
    } else if (event.fflags & NOTE_RENAME) {
      type = EVENT_RENAME;
      char buffer[MAXPATHLEN] = { 0 };
      fcntl(fd, F_GETPATH, buffer);
      close(fd);

      int length = strlen(buffer);
      path.resize(length);
      std::copy(buffer, buffer + length, path.data());
    } else if (event.fflags & NOTE_ATTRIB && lseek(fd, 0, SEEK_END) == 0) {
      // The file became empty, this does not fire as a NOTE_WRITE event for
      // some reason.
      type = EVENT_CHANGE;
    } else {
      continue;
    }

    PostEventAndWait(type, fd, path);
  }
}

WatcherHandle PlatformWatch(const char* path) {
  if (g_kqueue == -1) {
    return -g_init_errno;
  }

  int fd = open(path, O_EVTONLY, 0);
  if (fd < 0) {
    return -errno;
  }

  struct timespec timeout = { 0, 0 };
  struct kevent event;
  int filter = EVFILT_VNODE;
  int flags = EV_ADD | EV_ENABLE | EV_CLEAR;
  int fflags = NOTE_WRITE | NOTE_DELETE | NOTE_RENAME | NOTE_ATTRIB;
  EV_SET(&event, fd, filter, flags, fflags, 0, (void*)path);
  int r = kevent(g_kqueue, &event, 1, NULL, 0, &timeout);
  if (r == -1) {
    return -errno;
  }

  return fd;
}

void PlatformUnwatch(WatcherHandle fd) {
  close(fd);
}

bool PlatformIsHandleValid(WatcherHandle handle) {
  return handle >= 0;
}

int PlatformInvalidHandleToErrorNumber(WatcherHandle handle) {
  return -handle;
}
