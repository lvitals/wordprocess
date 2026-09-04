# WordProcess

WordProcess is a WordStar-like, keyboard-focused word processor for structured long-form writing. It provides terminal and graphical frontends, document sets, styles, configurable page layouts, rulers and tab stops, margin annotations, autosave, and import/export support for common text and document formats.

The native WordProcess document extension is `.wp`.

## Build

WordProcess uses Meson and Ninja. Required development libraries include a
system Lua implementation, ncursesw, libcmark, minizip, zlib, and stb headers.
The graphical frontend additionally requires GLFW, OpenGL, and XCB.
Spellchecking uses selectable plain-text word lists, one word per line. Meson
configures the directory scanned for installed dictionaries; it does not rely
on a language-ambiguous `words` alias.

```sh
meson setup builddir
meson compile -C builddir
meson test -C builddir
```

Select another dictionaries directory at build time with, for example:

```sh
meson setup builddir -Ddictionary_dir=/path/to/dictionaries
```

Distributors can set the version shown by the program and generated manual pages without editing source files:

```sh
meson setup builddir -Dapp_version=1.0.1
```

To build only the terminal frontend:

```sh
meson setup builddir -Dxwp=false
```

## Run

```sh
builddir/src/c/arch/ncurses/wp
builddir/src/c/arch/glfw/xwp
```

Open a document by supplying its path, for example:

```sh
wp manuscript.wp
```

Use `wp --help` for command-line conversion and scripting options.
Global configuration is stored in `~/.wordprocess/`.

## Documentation

The complete English documentation starts at [`docs/README.md`](docs/README.md).
Traditional Unix manual pages for the frontends, native format, and
configuration are available in `man/` and can be read directly, for example:

```sh
man ./man/wp.1
man ./man/wordprocess.5
```

## Document workflow

WordProcess files can contain multiple documents. Page-layout profiles provide
starting points for ABNT academic work and book manuscripts; every profile
value remains editable. Look and Feel settings control line wrapping,
hyphenation, paragraph entry behavior, editable TAB insertion and tab width,
and whether the configured page width is previewed or the full screen is used.

Supported import/export formats depend on the operation and include plain text,
Markdown, HTML, OpenDocument, LaTeX, troff, and Org mode.

## Project origin

WordProcess is a fork of WordGrinder. We thank David Given for creating and
maintaining the original project and for making that work available under the
MIT license.

## Copyright and license

WordProcess changes are copyright © 2026 Leandro V. Catarin. Portions inherited
from the original project remain copyright © 2007–2025 David Given and their
respective contributors.

The program is distributed under the MIT license. See
`licenses/COPYING.WordProcess`. Third-party notices are retained in `licenses/`.
