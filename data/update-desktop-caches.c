// Refreshes the icon theme and desktop file caches after `meson install`,
// so the freshly installed .desktop entry and its icon actually show up
// in the application menu instead of waiting for something else to
// invalidate those caches. Run via meson.add_install_script() in
// data/meson.build, which only wires this up when the underlying tools
// are present on the system (they're optional, not build dependencies).

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
    execlp(prog, prog, flag, path, (char *)NULL);
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

  const char *destdir_prefix = getenv("MESON_INSTALL_DESTDIR_PREFIX");
  if (!destdir_prefix) destdir_prefix = "";

  char datadir[4096];
  snprintf(datadir, sizeof datadir, "%s/%s", destdir_prefix, argv[1]);

  run_if_present("gtk-update-icon-cache", "icons/hicolor", "-qtf", datadir);
  run_if_present("update-desktop-database", "applications", "-q", datadir);
  return 0;
}
