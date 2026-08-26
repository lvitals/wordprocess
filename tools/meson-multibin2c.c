// Meson-friendly equivalent of the old `ab` build's tools/multibin2c.sh +
// build/_objectify.py, combined into one self-contained tool (no
// cwd-relative references, so it works from any Meson custom_target cwd).
//
// Usage: meson-multibin2c [--root DIR] <symbol> <file> ...
// Emits a `const FileDescriptor <symbol>[] = {...}` table to stdout,
// matching the FileDescriptor{ const char* data; size_t size; const char*
// name; } struct in src/c/globals.h (a plain C99 aggregate). Each file's
// embedded name is its path relative to DIR when --root is given.

#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// `path` may be given relative to the custom_target's cwd (which is not
// necessarily the project source root), so this can't just string-compare
// against `root` -- both need to be canonicalized first.
static const char *relative_to_root(const char *path, const char *canonical_root) {
  static char resolved[PATH_MAX];
  if (!canonical_root) return path;
  if (!realpath(path, resolved)) return path;

  size_t root_len = strlen(canonical_root);
  if (strncmp(resolved, canonical_root, root_len) == 0 && resolved[root_len] == '/') {
    return resolved + root_len + 1;
  }
  return path;
}

static unsigned char *read_file(const char *path, long *out_size) {
  FILE *f = fopen(path, "rb");
  if (!f) { perror(path); exit(1); }
  fseek(f, 0, SEEK_END);
  long size = ftell(f);
  fseek(f, 0, SEEK_SET);

  unsigned char *data = malloc(size > 0 ? (size_t)size : 1);
  if (size > 0 && fread(data, 1, (size_t)size, f) != (size_t)size) {
    fprintf(stderr, "%s: short read\n", path);
    exit(1);
  }
  fclose(f);

  *out_size = size;
  return data;
}

int main(int argc, char **argv) {
  int argi = 1;
  char canonical_root[PATH_MAX];
  const char *root = NULL;
  if (argi < argc && strcmp(argv[argi], "--root") == 0) {
    if (argi + 1 >= argc) {
      fprintf(stderr, "%s: --root requires an argument\n", argv[0]);
      return 1;
    }
    if (!realpath(argv[argi + 1], canonical_root)) {
      perror(argv[argi + 1]);
      return 1;
    }
    root = canonical_root;
    argi += 2;
  }

  if (argc - argi < 1) {
    fprintf(stderr, "Usage: %s [--root DIR] <symbol> <file> ...\n", argv[0]);
    return 1;
  }

  const char *symbol = argv[argi++];
  int nfiles = argc - argi;
  char **paths = &argv[argi];

  long *sizes = malloc(sizeof(long) * (size_t)nfiles);

  for (int i = 0; i < nfiles; i++) {
    long size;
    unsigned char *data = read_file(paths[i], &size);
    sizes[i] = size;

    printf("/* This is %s */\n", paths[i]);
    printf("static const uint8_t file_%d[] = {\n", i);
    for (long j = 0; j < size; j++) {
      printf("0x%02X,", data[j]);
      if (j % 16 == 15) printf("\n");
    }
    printf("\n};\n\n");

    free(data);
  }

  printf("const FileDescriptor %s[] = {\n", symbol);
  for (int i = 0; i < nfiles; i++) {
    printf("  { (const char*)file_%d, %ld, \"%s\" },\n", i, sizes[i],
           relative_to_root(paths[i], root));
  }
  printf("  {0}\n};\n");

  free(sizes);
  return 0;
}
