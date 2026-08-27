#!/usr/bin/env python3
"""Frontend smoke test: spawns the real `wp` binary in a pseudo-terminal and
checks a handful of properties that no Lua-level test can see, because they
live entirely in the ncurses frontend (src/c/arch/ncurses/dpy.c) -- below
the wg.getscreensize()/RedrawScreen() boundary the rest of tests/ mocks out.

This is deliberately NOT a full VT100 emulator or a byte-for-byte screen
comparison: that would be fragile and expensive to maintain. Instead it
checks a few specific, previously-bitten-by properties:

  - the process survives startup, being resized several times, and normal
    navigation, and exits cleanly on request (no hang, no crash);
  - after a resize, any cursor-positioning escape sequences that were
    emitted address a row/column that actually exists in the new size,
    rather than a stale one left over from before the resize;
  - with a locale that reports a non-UTF-8 codeset (e.g. a bare Linux
    console), the app never emits a raw byte the terminal couldn't render --
    it only ever uses the 7-bit-ASCII fallback glyphs and substitutes '?'
    for the rest (src/c/screen.c's dpy_writeunichar).

Run standalone as: tests/frontend/wp_pty_smoke.py <path-to-wp-binary>
"""

import fcntl
import os
import re
import select
import shutil
import struct
import sys
import tempfile
import termios
import time

TIMEOUT = 10.0

KEY_DOWN = b"\x1bOB"
KEY_UP = b"\x1bOA"
KEY_QUIT = b"\x11"  # Ctrl+Q, the "Exit" accelerator (see src/lua/menu.lua)


class Failure(Exception):
    pass


class WpProcess:
    """A `wp` process attached to its own pseudo-terminal."""

    def __init__(self, binary, home, rows, cols, term="xterm-256color", extra_env=None):
        self.rows = rows
        self.cols = cols
        env = dict(os.environ)
        env["HOME"] = home
        env["TERM"] = term
        # A from-scratch HOME has no settings.dat, so the app starts with
        # documented defaults (terminators on, Fixed scroll mode, etc.) --
        # exactly what the checks below rely on.
        if extra_env:
            env.update(extra_env)

        master, slave = os.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))

        pid = os.fork()
        if pid == 0:
            try:
                os.close(master)
                os.setsid()
                os.dup2(slave, 0)
                os.dup2(slave, 1)
                os.dup2(slave, 2)
                fcntl.ioctl(0, termios.TIOCSCTTY, 0)
                os.execve(binary, [binary], env)
            finally:
                os._exit(127)

        os.close(slave)
        self.pid = pid
        self.master = master

    def alive(self):
        try:
            return os.waitpid(self.pid, os.WNOHANG) == (0, 0)
        except ChildProcessError:
            return False

    def send(self, data):
        os.write(self.master, data)

    def drain(self, timeout):
        """Reads whatever output arrives within `timeout` seconds. Returns
        b'' on a plain idle timeout -- that's normal once the app has caught
        up and is waiting for the next key, not a failure by itself."""
        end = time.time() + timeout
        buf = b""
        while True:
            remaining = end - time.time()
            if remaining <= 0:
                break
            r, _, _ = select.select([self.master], [], [], remaining)
            if self.master not in r:
                break
            try:
                chunk = os.read(self.master, 65536)
            except OSError:
                break
            if not chunk:
                break
            buf += chunk
        return buf

    def resize(self, rows, cols):
        self.rows, self.cols = rows, cols
        fcntl.ioctl(self.master, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
        os.kill(self.pid, 28)  # SIGWINCH

    def wait_for_exit(self, timeout):
        end = time.time() + timeout
        while time.time() < end:
            if not self.alive():
                return True
            time.sleep(0.05)
        return False

    def kill(self):
        try:
            os.kill(self.pid, 9)
            os.waitpid(self.pid, 0)
        except (ProcessLookupError, ChildProcessError):
            pass


def require_alive(proc, label):
    if not proc.alive():
        raise Failure(f"{label}: process is no longer running")


def check_no_crash_text(data, label):
    if b"Lua error" in data or b"stack traceback" in data:
        raise Failure(f"{label}: output contains a Lua error:\n{data!r}")


# Matches the cursor-position forms this app's ncurses backend actually
# emits (see dpy_setcursor -> move() -> ncurses' cursor_address/row_address/
# column_address capabilities): CUP "row;colH", VPA "rowd", CHA "colG".
_CUP_RE = re.compile(rb"\x1b\[(\d+);(\d+)H")
_VPA_RE = re.compile(rb"\x1b\[(\d+)d")
_CHA_RE = re.compile(rb"\x1b\[(\d+)G")


def check_cursor_moves_in_bounds(data, rows, cols, label):
    """Every cursor-positioning sequence emitted must address a cell that
    actually exists in the *current* (post-resize) terminal size. A stale
    reference to the old size is exactly the class of bug a pure-Lua test
    (which never sees real terminal coordinates) cannot catch."""
    for m in _CUP_RE.finditer(data):
        row, col = int(m.group(1)), int(m.group(2))
        if row < 1 or row > rows or col < 1 or col > cols:
            raise Failure(
                f"{label}: cursor move to row {row}, col {col} is out of "
                f"bounds for a {cols}x{rows} terminal: {m.group(0)!r}")
    for m in _VPA_RE.finditer(data):
        row = int(m.group(1))
        if row < 1 or row > rows:
            raise Failure(
                f"{label}: cursor move to row {row} is out of bounds for a "
                f"{cols}x{rows} terminal: {m.group(0)!r}")
    for m in _CHA_RE.finditer(data):
        col = int(m.group(1))
        if col < 1 or col > cols:
            raise Failure(
                f"{label}: cursor move to col {col} is out of bounds for a "
                f"{cols}x{rows} terminal: {m.group(0)!r}")


def step_core_smoke(binary, home):
    """Spawn, resize through several sizes, navigate, and exit cleanly --
    the minimum bar: no hang, no crash, no leftover process."""
    proc = WpProcess(binary, home, rows=24, cols=80)
    try:
        proc.drain(3.0)  # let startup (including file/template loading) settle
        require_alive(proc, "after startup")

        proc.send(KEY_DOWN)
        data = proc.drain(0.5)
        require_alive(proc, "after Down")
        check_no_crash_text(data, "after Down")

        proc.send(KEY_UP)
        data = proc.drain(0.5)
        require_alive(proc, "after Up")
        check_no_crash_text(data, "after Up")

        for rows, cols in [(40, 120), (15, 40), (60, 200), (24, 80)]:
            proc.resize(rows, cols)
            data = proc.drain(0.5)
            require_alive(proc, f"after resize to {cols}x{rows}")
            check_no_crash_text(data, f"after resize to {cols}x{rows}")
            check_cursor_moves_in_bounds(data, rows, cols, f"after resize to {cols}x{rows}")

        proc.send(KEY_QUIT)
        if not proc.wait_for_exit(TIMEOUT):
            raise Failure("process did not exit within the timeout after Ctrl+Q")
    finally:
        if proc.alive():
            proc.kill()


def step_restricted_locale_ascii_only(binary, home):
    """With a locale that reports a non-UTF-8 codeset -- what a bare Linux
    console typically has -- the very first screen (which includes the
    terminator ruler, on by default) must never contain a raw byte >= 0x80.
    Every symbol table in redraw.lua has a plain-ASCII fallback selected via
    UseUnicode(); this is the property that fallback exists to guarantee."""
    proc = WpProcess(
        binary, home, rows=24, cols=80, term="linux",
        extra_env={"LC_ALL": "C", "LANG": "C"})
    try:
        data = proc.drain(3.0)
        require_alive(proc, "restricted-locale startup")
        check_no_crash_text(data, "restricted-locale startup")

        high_bytes = [b for b in data if b >= 0x80]
        if high_bytes:
            raise Failure(
                f"restricted-locale startup emitted {len(high_bytes)} byte(s) "
                f">= 0x80, which a bare Linux console (TERM=linux, non-UTF-8 "
                f"locale) cannot render:\n{data!r}")

        proc.send(KEY_QUIT)
        if not proc.wait_for_exit(TIMEOUT):
            raise Failure("process did not exit within the timeout after Ctrl+Q")
    finally:
        if proc.alive():
            proc.kill()


def main():
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <path-to-wp-binary>", file=sys.stderr)
        return 2
    binary = sys.argv[1]
    if not os.path.isfile(binary) or not os.access(binary, os.X_OK):
        print(f"not an executable file: {binary}", file=sys.stderr)
        return 2

    steps = [step_core_smoke, step_restricted_locale_ascii_only]
    for step in steps:
        home = None
        try:
            home = tempfile.mkdtemp(prefix="wp-pty-smoke-")
            os.makedirs(os.path.join(home, ".wordprocess"), exist_ok=True)
            step(binary, home)
        except Failure as e:
            print(f"FAIL: {step.__name__}: {e}", file=sys.stderr)
            return 1
        finally:
            if home:
                shutil.rmtree(home, ignore_errors=True)

    print("ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
