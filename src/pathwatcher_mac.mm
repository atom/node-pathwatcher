#include "common.h"

#include <errno.h>
#include <unistd.h>
#include <sys/event.h>
#include <sys/param.h>
#include <sys/time.h>
#include <sys/types.h>

static int g_kqueue;

void PlatformInit() {
  g_kqueue = kqueue();

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
    char path[MAXPATHLEN];
    path[0] = 0;

    if (event.fflags & NOTE_WRITE) {
      type = CHANGE;
    } else if (event.fflags & NOTE_DELETE) {
      type = DELETE;
    } else if (event.fflags & NOTE_RENAME) {
      type = RENAME;
      fcntl(fd, F_GETPATH, &path);
    } else {
      continue;
    }

    PostEvent(type, fd, path);

    WaitForMainThread();
  }
}

int PlatformWatch(const char* path) {
  int fd = open(path, O_EVTONLY, 0);
  if (fd < 0) {
    fprintf(stderr, "Cannot create kevent for %s with errno %d\n", path, errno);
    perror("open");
    return fd;
  }

  struct timespec timeout = { 0, 0 };
  struct kevent event;
  int filter = EVFILT_VNODE;
  int flags = EV_ADD | EV_ENABLE | EV_CLEAR;
  int fflags = NOTE_WRITE | NOTE_DELETE | NOTE_RENAME;
  EV_SET(&event, fd, filter, flags, fflags, 0, (void*)path);
  kevent(g_kqueue, &event, 1, NULL, 0, &timeout);

  return fd;
}

void PlatformUnwatch(int fd) {
  close(fd);
}

bool PlatformIsHandleValid(int handle) {
  return handle >= 0;
}

