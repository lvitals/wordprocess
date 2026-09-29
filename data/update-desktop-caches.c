// Refreshes the icon theme, desktop file, and shared-mime-info caches after
// `make install`, so the freshly installed .desktop entry, its icon, and
// the *.wp/*.wg file association actually show up instead of waiting for
// something else to invalidate those caches. Without the mime cache refresh
// specifically, wordprocess.xml sits in mime/packages unused and *.wp keeps
// resolving to whatever other package's glob already claims it (e.g.
// shared-mime-info's own application/vnd.wordperfect). Run via
// Makefile.am invokes this helper from install-data-hook. The underlying
// cache tools are optional, not build dependencies.

#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <unistd.h>

static void run_if_present(const char *prog, const char *subdir, const char *flag,
                            const char *datadir) {
  char path[4096];
  snprintf(path, sizeof path, "%s/%s", datadir, subdir);

  pid_t pid = fork();
  if (pid == 0) {
    /* update-mime-database takes no flag, just the mime directory; the
     * other two tools here always want one before the path. */
    if (flag)
      execlp(prog, prog, flag, path, (char *)NULL);
    else
      execlp(prog, prog, path, (char *)NULL);
    _exit(127); /* prog not found on PATH */
  } else if (pid > 0) {
    int status;
    waitpid(pid, &status, 0);
  }
}

int main(int argc, char **argv) {
  if (argc != 2) {
    fprintf(stderr, "usage: %s <datadir>\n", argv[0]);
    return 1;
  }

  if (getenv("DESTDIR")) {
    /* Staged install (packaging): this tree isn't the live system, so the
     * cache update belongs to the package's own post-install step instead. */
    return 0;
  }

  run_if_present("gtk-update-icon-cache", "icons/hicolor", "-qtf", argv[1]);
  run_if_present("update-desktop-database", "applications", "-q", argv[1]);
  run_if_present("update-mime-database", "mime", NULL, argv[1]);
  return 0;
}
