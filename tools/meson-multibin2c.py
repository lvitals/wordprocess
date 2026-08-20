#!/usr/bin/env python3
# Meson-friendly equivalent of tools/multibin2c.sh + build/_objectify.py
# combined into one self-contained script (no cwd-relative references to the
# `ab` build tree, so it works from any Meson custom_target cwd).
#
# Usage: meson-multibin2c.py <symbol> <file>[=<display-name>] ...
# Emits a `const FileDescriptor <symbol>[] = {...}` table to stdout, matching
# the FileDescriptor{ const char* data; size_t size; const char* name; }
# struct in src/c/globals.h (a plain C99-and-C++ aggregate -- no std::string).

import os
import sys


def main():
    args = sys.argv[1:]
    root = None
    if args[:1] == ["--root"]:
        root = args[1]
        args = args[2:]

    if len(args) < 1:
        sys.exit(f"Usage: {sys.argv[0]} [--root DIR] <symbol> <file> ...")

    symbol = args[0]
    entries = []
    for i, path in enumerate(args[1:]):
        display = os.path.relpath(path, root) if root else path
        var = f"file_{i}"
        with open(path, "rb") as f:
            data = f.read()

        print(f"/* This is {path} */")
        print(f"static const uint8_t {var}[] = {{")
        for j in range(0, len(data), 16):
            print("".join(f"0x{b:02X}," for b in data[j:j + 16]))
        print("};")
        print()

        entries.append((var, len(data), display))

    print(f"const FileDescriptor {symbol}[] = {{")
    for var, length, display in entries:
        print(f'  {{ (const char*){var}, {length}, "{display}" }},')
    print("  {0}")
    print("};")


if __name__ == "__main__":
    main()
