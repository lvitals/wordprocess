# Keyboard shortcuts

WordProcess shows the shortcuts that are active for the current document set in
**Main Menu > Keyboard shortcuts** (`Alt-?`, or `Escape` then `?`). This is the
best reference after changing a binding. In that window, use `J`/`K` to move by
line, `H`/`L` to move by page, and `Escape`, `Q`, or `Enter` to close it.

While any menu is open, `H`/`J`/`K`/`L` navigate left/down/up/right, alongside
the arrow keys.

In configuration forms, `J`/`K` move between controls and `H`/`L` change the
selected value. In lists, `H`/`L` move by page. Text fields keep these letters
available for normal typing; use `Tab` and `Shift-Tab` to move to the next or
previous control. In numeric fields, `J`/`K` change focus and `H`/`L` move the
text cursor, alongside the arrow keys.

File selectors start with the file list focused. Use `J`/`K` or up/down to
select a file, `H` or left to open the parent directory, and `L`, right, or
Enter to open the selection. `Tab` alternates between the list and the filename
field; while that field is focused, letters edit the filename normally.

The names below use `Ctrl`, `Alt`, and `Shift`. A slash separates alternatives;
`Shift` combined with a movement extends the selection.

## Standard editing shortcuts

### Files and editing

| Shortcut | Default action |
| --- | --- |
| `Escape` or `Menu` | Open the main menu |
| `Ctrl-Q` | Exit, asking about unsaved work |
| `Ctrl-S` | Save the current document set |
| `Ctrl-O` | Load a document set |
| `Ctrl-X` | Cut the selection |
| `Ctrl-C` | Copy the selection |
| `Ctrl-V` | Paste |
| `Ctrl-Z` | Undo |
| `Ctrl-Y` | Redo |
| `Ctrl-F` | Open Find and Replace |
| `Ctrl-K` | Find the next match |
| `Ctrl-R` | Replace the current match, then find the next one |
| `Ctrl-G` | Go to an H1–H4 heading, estimated page, line, or percentage |
| `Ctrl-L` | Find the next misspelt word |
| `Ctrl-M` | Add the current word to the user dictionary |

### Navigation, selection, and deletion

| Shortcut | Default action |
| --- | --- |
| `Left` / `Right` | Move one character |
| `Up` / `Down` | Move one displayed line |
| `Ctrl-Left` / `Ctrl-Right` | Move to the previous/next word |
| `Ctrl-Up` / `Ctrl-Down` | Move to the previous/next paragraph |
| `Home` / `End` | Move to the beginning/end of the displayed line |
| `Ctrl-Home` / `Ctrl-End` | Move to the beginning/end of the document |
| `Page Up` / `Page Down` | Move one viewport page up/down |
| `Shift` plus any movement above | Select to the movement destination |
| `Ctrl-W` | Select the current word |
| `Ctrl-Space` or `Ctrl-@` | Toggle the selection mark |
| `Backspace` / `Delete` | Delete the selection or previous/next character |
| `Ctrl-E` | Delete a word |

`Ctrl-Space` is reported as `Ctrl-@` by some terminals. Mouse-wheel up/down is
treated like cursor up/down. Previous/next inserted tabulation and delete
current paragraph are also available in the Navigation menu, but have no
conventional shortcut by default.

### Styles and text entry

| Shortcut | Default action |
| --- | --- |
| `Ctrl-I` | Apply italic style |
| `Ctrl-U` | Apply underline style |
| `Ctrl-B` | Apply bold style |
| `Ctrl-N` | Clear character styling (normal) |
| `Ctrl-P` | Choose a paragraph style |
| `Space` | Insert a space |
| `Enter` | Start a new paragraph |
| `Tab` | Insert a tabulation when Tab insertion is enabled |

Text-entry keys, `Escape`, `Menu`, and the keys used to operate menus and
dialogs are handled directly and cannot be reassigned as menu shortcuts.

## Compact-keyboard navigation

WordProcess provides three equivalent ways to use letter-based navigation:

- Hold `Ctrl-Alt` and press a command key for a direct one-step shortcut.
- Press `Alt-;`, release it, then press a command key for a one-step command
  layer. `Escape` cancels the pending command.
- Press `Alt-N` (or `Escape`, then `N`) to enter persistent Navigation mode.
  Press `I`, `Escape`, or `Alt-N` to return to writing mode. While it is active,
  printable keys below navigate instead of inserting text; modified standard
  shortcuts continue to work.

| Command key | Direct chord | Default action |
| --- | --- | --- |
| `H` / `J` / `K` / `L` | `Ctrl-Alt-H/J/K/L` | Move left/down/up/right |
| `B` / `W` | `Ctrl-Alt-B/W` | Move to the previous/next word |
| `[` / `]` | `Ctrl-Alt-I/O` | Move to the previous/next inserted tabulation |
| `A` / `E` | `Ctrl-Alt-A/E` | Move to the beginning/end of the displayed line |
| `U` / `D` | `Ctrl-Alt-U/D` | Move one viewport page up/down |
| `T` / `G` | `Ctrl-Alt-T/G` | Move to the beginning/end of the document |
| `X` / `Shift-X` | `Ctrl-Alt-X` / `Ctrl-Alt-Shift-X` | Delete the next/previous character |
| `Shift-D` | `Ctrl-Alt-Shift-D` | Delete the current paragraph |
| `?` | — | Open the keyboard reference |

`Alt-?` opens the keyboard reference and `Alt-N` toggles Navigation mode.
Terminal key encoding varies: if a chord is not distinguishable in `wp`, use
the command layer, Navigation mode, a different binding, or the `xwp` frontend.

## Customising shortcuts in the menus

Menu customisation travels with the current `.wp` document set:

1. Open the menu with `Escape` or the `Menu` key and highlight the command to
   change. Navigation commands are under **Navigation**.
2. Press `Ctrl-V`, then press the new shortcut.
3. Save the document set with `Ctrl-S`.

The new key must be a non-printing key combination recognised by the frontend,
must not be `Escape` or a resize event, and must not already be assigned. If it
is already used, unbind the old command first. While a menu is open:

| Key | Customisation action |
| --- | --- |
| `Ctrl-V` | Bind the highlighted item to the next key pressed |
| `Ctrl-X` | Remove the highlighted item's shortcut |
| `Ctrl-R` | Reset every menu shortcut to its default after confirmation |

Resetting marks the document set as modified. Saving a preferred setup as a
template is a convenient way to reuse its bindings in new document sets.

## Machine-wide overrides with Lua

For bindings that should apply on one machine to every document set, put
`OverrideKey(KEY, ACTION)` calls in `~/.wordprocess/startup.lua`. These trusted
Lua overrides take precedence over defaults and per-set menu customisations,
are not stored in `.wp` files, and are not changed by the menu's bind/unbind
commands.

```lua
-- Make Ctrl-Z toggle the selection mark instead of undoing.
OverrideKey("^Z", "ZM")

-- Use F1 and F2 to select the first and second documents.
OverrideKey("F1", "D1")
OverrideKey("F2", "D2")

-- Reverse H and L in the one-step command layer.
OverrideKey("COMMAND_H", "ZR")
OverrideKey("COMMAND_L", "ZL")

-- Reverse H and L in persistent Navigation mode too.
OverrideKey("NAV_H", "ZR")
OverrideKey("NAV_L", "ZL")
```

The first argument uses WordProcess's internal key vocabulary:

| Notation | Meaning | Examples |
| --- | --- | --- |
| `^` | Ctrl | `^S`, `^LEFT` |
| `S` before a named key | Shift | `SLEFT`, `SPGDN` |
| `A` | Alt | `AH`, `AN` |
| `A^` / `AS^` | Ctrl-Alt / Ctrl-Alt-Shift | `A^H`, `AS^X` |
| Named keys | Non-printing keys | `LEFT`, `HOME`, `PGDN`, `F1` |
| `COMMAND_...` | Key after the `Alt-;` command prefix | `COMMAND_H`, `COMMAND_SHIFT_D` |
| `NAV_...` | Printable key in Navigation mode | `NAV_H`, `NAV_QUESTION` |

For command-layer and Navigation-mode names, use `LEFTBRACKET`,
`RIGHTBRACKET`, `SHIFT_X`, `SHIFT_D`, and `QUESTION` rather than punctuation.
Direct compact chords use names such as `A^H` and `AS^D`. Key names exclude the
`KEY_` prefix produced internally by a frontend.

The second argument is a menu action ID. List all IDs supported by the running
version with:

```sh
wp --exec 'ListMenuItems()'
```

Common IDs include `FS` (save), `FO` (load), `FQ` (exit), `ET`/`EC`/`EP`
(cut/copy/paste), `Eundo`/`Eredo`, `ZL`/`ZR`/`ZU`/`ZD` (movement), `ZWL`/`ZWR`
(word movement), `ZH`/`ZE` (line boundaries), `ZBD`/`ZED` (document
boundaries), `ZDPC`/`ZDNC` (character deletion), `ZDPARA` (paragraph deletion),
`ZM` (selection mark), `ZMODE` (Navigation mode), and `Hkeys` (keyboard help).
Document IDs (`D1`, `D2`, ...) and paragraph-style IDs (`SP1`, `SP2`, ...) are
generated from the current document set.

After editing `startup.lua`, restart WordProcess. Use the in-program keyboard
reference to verify the active result. A startup override can map a key to an
existing action or Lua function; misspelled action IDs are only reported when
the key is used, so copy IDs from `ListMenuItems()` exactly.

## Frontend limitations and troubleshooting

- `wp` receives the key sequences exposed by ncurses and the terminal. Some
  terminals cannot distinguish Shift/Ctrl plus arrows, function-key modifiers,
  `Ctrl-Space`, or `Tab` from `Ctrl-I`.
- `xwp` generally distinguishes more modifier combinations, but operating
  system and keyboard-layout reservations still apply.
- If a shortcut does nothing, open the keyboard reference to see its active
  action, check for a startup override, and try the key in the other frontend.
- An unknown platform key can appear as `UNKNOWN_1234` or a similar name. It
  may still be bound, though its displayed label is less useful.
