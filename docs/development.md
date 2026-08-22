# Development guide

## Architecture

The native C layer owns process startup, Lua integration, Unicode word
operations, filesystem access, ZIP/compression, clipboard integration, and the
frontend abstraction. `src/c/arch/ncurses` implements `wp`; `src/c/arch/glfw`
implements `xwp`. Both link the same common engine and embedded Lua source
table.

Lua implements documents, paragraphs, navigation, editing, forms, menus,
rendering, import/export, persistence, settings, and feature add-ons. The
startup sequence initialises C subsystems, loads all embedded Lua sources,
creates the document set, loads global settings, parses arguments, then starts
the selected frontend's event loop.

## Source map

| Path | Responsibility |
| --- | --- |
| `src/c/` | Native bridge and shared executable code |
| `src/c/arch/ncurses/` | Terminal display/input |
| `src/c/arch/glfw/` | Graphical display/input and embedded fonts |
| `src/lua/` | Editor engine and interface |
| `src/lua/addons/` | Optional features registered through events |
| `src/lua/import/` | HTML, Markdown, ODT, and text importers |
| `src/lua/export/` | HTML, LaTeX, Markdown, ODT, Org, text, and troff exporters |
| `tests/` | Lua functional/regression suite |
| `testdocs/` | Native compatibility and ODT fixtures |
| `scripts/` | Automation and diagnostic Lua scripts |
| `extras/` | Desktop integration, MIME type, fonts, icon, dictionaries |

## Build system

Meson generates an embedded Lua table with `tools/meson-multibin2c.py` and,
for `xwp`, font and icon sources. Build options are `xwp`, `app_version`, and
`lua_version`, and `dictionary_path`. The build detects stb headers in `/usr/include/stb` or
`/usr/local/include/stb`. The native format constant is currently 8.

The spelling word list is optional and is never a link-time dependency. Meson
reports whether `dictionary_path` exists and warns when it does not. The file
must contain one complete word per line; Hunspell `.dic`/`.aff` files are not
directly compatible and must first be expanded to a plain word list.

Run the normal verification cycle with:

```sh
meson setup builddir
meson compile -C builddir
meson test -C builddir --print-errorlogs
```

The tests invoke Lua scenarios through the built executable and cover editing,
navigation, styles, wrapping, clipboard, persistence compatibility, import and
export, page layout, settings, argument parsing, filesystem behaviour, and
reported regressions. `tests/valgrind.sh` supports memory checking where
Valgrind is available.

## Adding features

Prefer a Lua add-on plus event registration when a feature does not require a
new native capability. Add user-visible actions to `menu.lua`, create an undo
checkpoint before mutation, call the appropriate `touch` method, invalidate
wrap data when display geometry changes, and queue a redraw. Store portable
document behaviour under `documentSet.addons`; store machine/UI preferences in
`GlobalSettings`.

An importer must build a new `Document` with `CreateImporter`; an exporter
should render through `ExportFileUsingCallbacks` so paragraph structure and
inline style transitions remain consistent. Add round-trip or golden-output
tests for every supported style.

When changing native serialization, increment the file format, retain explicit
upgrade paths, and add a fixture proving older files still load. Never describe
an internal native file as editable text.

## Packaging

Meson installs both enabled executables and desktop integration resources.
Distributors should set `app_version`, install the manual pages from `man/`,
and may disable `xwp` for terminal-only packages. Preserve `NOTICE`, the main
MIT licence, third-party licences, bundled dictionary notices, and the project
origin acknowledgement.
