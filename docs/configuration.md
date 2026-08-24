# Configuration

## Locations

`~/.wordprocess` is created on startup. The default files and directories are:

| Path | Purpose |
| --- | --- |
| `~/.wordprocess/startup.lua` | User Lua configuration loaded before the UI |
| `~/.wordprocess/settings.dat` | Serialised global settings |
| `~/.wordprocess/templates/` | User templates and optional `default.wp` |

`startup.lua` can also define machine-wide keyboard overrides. See
[Keyboard shortcuts](keyboard-shortcuts.md#machine-wide-overrides-with-lua) for
the precedence rules, key notation, and examples.

`GlobalSettings.large_file_threshold` selects the native mapped piece-table
backend for plain-text imports and defaults to 64 MiB. See
[Large text files](large-text-files.md).

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
Dictionary chooses the global word-list files. Recent files and optional debug
status terms are also stored globally.

The checker expects UTF-8 plain text with one complete word per line. Multiple
word lists can be enabled together under **Spellchecker → Configure
Spellchecker**. Its language list uses `[x]` for enabled entries; use the arrow
keys to select an entry and Space to toggle as many languages as needed. The
dialog discovers every real file in the build-configured dictionary directory,
previously added files, and `*.words` files in `~/.wordprocess`. Symbolic-link
aliases are omitted to avoid duplicate or language-ambiguous entries. Any compatible word list
can be added under **Global settings → Load new system dictionary**. The same
directory can be compiled in with `-Ddictionary_dir=/path/to/dictionaries`.
An optional initial selection uses
`-Ddictionary_path=/path/to/plain-word-list`. Dictionary formats containing
affix rules or other metadata are not accepted directly; convert them to a
plain word list first. See [Converting a Hunspell dictionary to a word
list](hunspell-wordlists.md). Lists do not need to use a particular sort order;
they are queried through a compact page-prefix index. Only candidate pages are
read for each lookup, and a bounded result cache keeps redraw and navigation
responsive without loading the complete dictionaries into Lua tables.

Words which are absent from all selected dictionaries are shown in red and
underlined. **Spellchecker → Find next misspelt word** selects the next unknown
word. The built-in checker identifies unknown words but does not currently
generate replacement suggestions.

## Per-set and per-document settings

Autosave, scrapbook, and smart quotes belong to the document set and travel
with its `.wp` file. Page layout, its physical `Pg:` calculation, cursor, margin display
mode, and content belong to each document.

HTML export has its own document-set configuration controlling generated HTML.
Because exporters consume structural paragraph styles, presentation settings
do not alter native content.

Menu accelerators, status-bar visibility, search/replace text, spellchecker
preferences, user-dictionary words, and the local file path are editor state.
They are not written into `.wp` files. When an older file contains a hidden
`User dictionary` document, its words are migrated to global settings and that
internal document is removed.

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
