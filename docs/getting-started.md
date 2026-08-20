# Getting started

WordProcess is a Unicode-aware, keyboard-focused word processor for structured
long-form writing. It uses the same editing engine through two frontends:
`wp`, an ncurses terminal application, and `xwp`, a GLFW/OpenGL graphical
application. A native `.wp` file is a document set and may contain several
named documents.

## Build and install

The build requires Meson, Ninja, a C compiler, Python 3, pkg-config, libcmark,
minizip, zlib, stb headers, ncursesw, and Lua 5.1 through 5.5. Building `xwp`
also requires GLFW, OpenGL, and XCB.

```sh
meson setup builddir
meson compile -C builddir
meson test -C builddir
meson install -C builddir
```

Useful configuration options are:

```sh
meson setup builddir -Dxwp=false                 # terminal frontend only
meson setup builddir -Dlua_version=5.4           # select a Lua ABI
meson setup builddir -Dapp_version=1.0.1         # reported version
```

When `lua_version=auto`, the build searches from Lua 5.5 down to 5.1. The
project is written in GNU C99 and embeds its Lua sources; `xwp` also embeds its
four default Fantasque Sans Mono fonts and application icon.

## Start a session

```sh
wp
wp manuscript.wp
xwp manuscript.wp
wp --recent
```

With no file, WordProcess loads `~/.wordprocess/templates/default.wp` when it
exists and matches the current file format; otherwise it creates a blank set.
If a command-line path does not exist, the editor starts a new document set
with that path already selected for saving.

Press Escape to open the menu. Menu letters choose an entry. Arrow keys move
the cursor; Shift plus a movement key extends a selection. Printable text is
inserted directly. Space separates words, Return starts a paragraph, and Tab
inserts editable spacing when enabled.

Save with Ctrl-S and exit with Ctrl-Q. A native save writes the entire document
set, including all documents, document settings, page layouts, clipboard data,
and enabled add-on settings.

## Editing model

Content is stored as paragraphs containing words. Character style changes are
embedded in the word stream, while every paragraph has a structural style such
as body text, heading, list item, quotation, or raw output. This model allows
exporters to produce semantic HTML, Markdown, OpenDocument, LaTeX, troff, Org,
and plain text instead of merely copying the screen appearance.

The cursor is a paragraph/word/byte-offset position. A mark plus the cursor
defines the active selection. Copy and cut preserve WordProcess styling through
an application-specific clipboard representation and also publish plain text
for other applications.

## Command-line overview

```sh
wp --help
wp --version
wp --convert notes.md notes.wp
wp --convert book.wp:"Chapter 1" chapter1.odt
wp --lua scripts/exportall.lua book.wp output.html
wp --exec 'print(VERSION)'
```

See [Import and export](import-export.md) and [Scripting](scripting.md) for the
precise rules.

