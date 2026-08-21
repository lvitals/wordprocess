# Editor reference

For the complete default key map, compact-keyboard navigation, and both ways to
customise bindings, see [Keyboard shortcuts](keyboard-shortcuts.md).

## Direct keys

| Key | Action |
| --- | --- |
| Escape or Menu | Open the main menu |
| Ctrl-Q | Exit, prompting when unsaved work exists |
| Ctrl-S | Save the current document set |
| Ctrl-O | Open a document set |
| Arrow keys | Move by display line or character |
| Ctrl-Left / Ctrl-Right | Move by word |
| Ctrl-Up / Ctrl-Down | Move by paragraph |
| Home / End | Move to the display line boundary |
| Ctrl-Home / Ctrl-End | Move to the document boundary |
| Page Up / Page Down | Move by viewport page |
| Shift plus movement | Extend the selection |
| Ctrl-W | Select the current word |
| Ctrl-Space | Toggle the selection mark |
| Backspace / Delete | Delete the selection or adjacent character |
| Ctrl-E | Delete a word |
| Ctrl-X / Ctrl-C / Ctrl-V | Cut, copy, and paste |
| Ctrl-Z / Ctrl-Y | Undo and redo |
| Ctrl-F / Ctrl-K | Find and find next |
| Ctrl-R | Replace, then find the next match |
| Ctrl-G | Open the structural table of contents (H1–H4) |
| Ctrl-I / Ctrl-U / Ctrl-B / Ctrl-N | Italic, underline, bold, or normal |
| Ctrl-P | Choose a paragraph style |
| Ctrl-L | Find the next misspelt word |
| Ctrl-M | Add the current word to the user dictionary |

`Ctrl-Space` may be reported as `Ctrl-@` by a terminal. Accelerator availability
depends on what the terminal can distinguish. The menu always exposes the same
operations.

## File menu

The File menu creates a new set, loads or saves a set, opens recent files,
creates from or saves as a template, adds a blank document, imports a new
document, exports the current document, manages documents, configures global
or per-set features, shows version information, and exits.

Import adds a new named document to the current set. Export writes only the
current document. Native Save writes the complete set.

## Edit menu

Cut, Copy, Paste, and Delete operate on the selection. Undo and Redo use
checkpoints created before editing operations. Find supports replacement;
Find Next repeats the active search, and Replace Then Find replaces the current
match before advancing.

Smartquotify and Unsmartquotify transform the selected content using the
configured quotation characters. The scrapbook submenu copies or moves a
selection into a designated document and can paste that stored fragment back.
The spellchecker submenu navigates misspellings and updates the user dictionary.

## Style menu

Italic, bold, and underline are character styles and can overlap. Normal clears
all character styling. Paragraph style describes structure and affects display,
numbering, Enter-key continuation, and exporters. Margin mode can show nothing,
paragraph style names, paragraph numbers, or per-paragraph word counts. The
status bar can be toggled per document set.

## Documents menu

Every `.wp` file contains one or more documents. The Documents menu switches
the current document. Manage Documents can add, rename, delete, and reorder
documents. The final remaining document cannot be deleted, and names must be
unique inside the set.

## Navigation and selection

The Navigation menu exposes every cursor and selection command, including
character, word, paragraph, display-line, page, and document boundaries.
Starting a Shift movement sets the mark; subsequent movement changes the
selection endpoint. A non-Shift movement collapses or clears selection state as
appropriate. Typing, Space, Return, Tab, deletion, paste, and style changes
replace selected content when their operation supports it.

## Display behaviour

The editor can use the full viewport, an explicit maximum column width, or a
physical-page preview derived from the current document's dimensions, margins,
and font size. Long words are either moved intact or visually hyphenated.
Scrolling can keep the cursor fixed while content moves or jump the viewport.

The status bar combines available terms by priority: document name and modified
state, cursor position, word count, approximate page count, character style,
and optional debugging information. Narrow windows omit lower-priority terms.

Both frontends accept mouse selection. Pressing starts a mark, dragging extends
it, and a click without a drag clears it. The graphical frontend also receives
window resize and close events.
