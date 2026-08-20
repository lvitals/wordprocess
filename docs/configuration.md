# Configuration

## Locations

`~/.wordprocess` is created on startup. The default files and directories are:

| Path | Purpose |
| --- | --- |
| `~/.wordprocess/startup.lua` | User Lua configuration loaded before the UI |
| `~/.wordprocess/settings.dat` | Serialised global settings |
| `~/.wordprocess/templates/` | User templates and optional `default.wp` |
| `~/.wordprocess/user.dictionary` | User spelling dictionary, when enabled |

`startup.lua` can also define machine-wide keyboard overrides. See
[Keyboard shortcuts](keyboard-shortcuts.md#machine-wide-overrides-with-lua) for
the precedence rules, key notation, and examples.

On Windows the configuration directory is beside the executable. `--config`
selects another startup Lua file for one invocation; it does not relocate
`settings.dat`.

## Global settings

Look and Feel configures editor width (`Full width`, `Column limit`, or `Page
preview`), column limit (minimum 20), document terminators, first-line indent,
paragraph spacing, an extra display space after full stops, theme, fixed/jump
scrolling, move-word/hyphenate wrapping, Tab insertion, and Tab width (1–16).

GUI configures the default window width and height (both at least 50 pixels),
font size, and regular, italic, bold, and bold-italic font paths. The bundled
Fantasque fonts are defaults. Changes reinitialise the frontend.

Directories configures the template directory and an optional central autosave
directory. Missing writable directories can be created from the dialog.
Dictionary chooses the global word-list file. Recent files and optional debug
status terms are also stored globally.

## Per-set and per-document settings

Autosave, scrapbook, smart quotes, spellchecker, approximate page count,
clipboard, status-bar visibility, and user dictionary belong to the document
set and travel with its `.wp` file. Page layout, cursor, margin display mode,
and content belong to each document.

HTML export has its own document-set configuration controlling generated HTML.
Because exporters consume structural paragraph styles, presentation settings
do not alter native content.

## Frontend and locale behaviour

`wp` uses ncursesw and the terminal's key encoding. It enables Unicode when the
locale reports UTF-8; `--no-unicode` or `-8` forces an ISO-8859-1-compatible
display character set. `--no-ncurses-colour` is accepted for compatibility but
currently performs no action.

`xwp` uses GLFW/OpenGL and the same menus, commands, settings, and document
engine. It renders with four font faces and supports mouse drag selection.

## Safe recovery

If the editor reports an internal error, save immediately under a different
name. Look for configured autosave files if the primary file is unavailable.
A failed native save may leave `FILE.wp.new`; it contains the newly written
candidate if replacement could not complete. Do not overwrite recovery copies
until a known-good document has been opened and verified.
