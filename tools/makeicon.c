// Rasterizes the already-128x128 window icon PNG (produced by rsvg-convert
// in src/c/arch/glfw/meson.build) into raw RGBA pixel data and emits it as
// a `const unsigned char icon_data[]` C array, for glfwSetWindowIcon() (see
// src/c/arch/glfw/main.c). Tries whichever of ImageMagick's magick/convert
// or ffmpeg is available on PATH, in that order.
//
// Usage: makeicon <png-path>

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <unistd.h>

#define ICON_SIDE 128
#define ICON_BYTES (ICON_SIDE * ICON_SIDE * 4)

// Runs argv (execvp-style, NULL-terminated) and captures its stdout.
// Returns NULL if argv[0] isn't on PATH, it exits non-zero, or its output
// isn't a full ICON_SIDE x ICON_SIDE RGBA frame.
static unsigned char *try_convert(char *const argv[], size_t *out_size) {
  int pipefd[2];
  if (pipe(pipefd) != 0) { perror("pipe"); exit(1); }

  pid_t pid = fork();
  if (pid < 0) { perror("fork"); exit(1); }

  if (pid == 0) {
    close(pipefd[0]);
    dup2(pipefd[1], STDOUT_FILENO);
    close(pipefd[1]);
    int devnull = open("/dev/null", O_WRONLY);
    if (devnull >= 0) { dup2(devnull, STDERR_FILENO); close(devnull); }
    execvp(argv[0], argv);
    _exit(127); // argv[0] not found on PATH
  }
  close(pipefd[1]);

  size_t cap = ICON_BYTES + 4096, len = 0;
  unsigned char *buf = malloc(cap);
  ssize_t n;
  while ((n = read(pipefd[0], buf + len, cap - len)) > 0) {
    len += (size_t)n;
    if (len == cap) {
      cap *= 2;
      buf = realloc(buf, cap);
    }
  }
  close(pipefd[0]);

  int status;
  waitpid(pid, &status, 0);

  if (!WIFEXITED(status) || WEXITSTATUS(status) != 0 || len != ICON_BYTES) {
    free(buf);
    return NULL;
  }

  *out_size = len;
  return buf;
}

int main(int argc, char **argv) {
  if (argc != 2) {
    fprintf(stderr, "usage: %s <png-path>\n", argv[0]);
    return 1;
  }
  char *path = argv[1];

  char *magick_argv[] = {"magick", path, "-resize", "128x128!", "rgba:-", NULL};
  char *convert_argv[] = {"convert", path, "-resize", "128x128!", "rgba:-", NULL};
  char *ffmpeg_argv[] = {
    "ffmpeg", "-v", "error", "-i", path, "-s", "128x128",
    "-f", "rawvideo", "-pix_fmt", "rgba", "-", NULL,
  };

  size_t size = 0;
  unsigned char *data = try_convert(magick_argv, &size);
  if (!data) data = try_convert(convert_argv, &size);
  if (!data) data = try_convert(ffmpeg_argv, &size);

  if (!data) {
    fprintf(stderr,
      "%s: could not process icon: neither ImageMagick (magick/convert) "
      "nor ffmpeg found on PATH.\n", argv[0]);
    return 1;
  }

  printf("extern const unsigned char icon_data[];\n");
  printf("const unsigned char icon_data[] = {\n");
  for (size_t i = 0; i < size; i++) {
    printf("%s%u", i ? ", " : "", data[i]);
  }
  printf("\n};\n");

  free(data);
  return 0;
}
