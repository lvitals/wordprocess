# Scripting and extension

WordProcess embeds system PUC-Rio Lua and loads its editor implementation as
embedded Lua modules. Scripting is powerful and intentionally trusted: scripts
run with the process's file-system permissions.

## Command-line execution

```sh
wp --lua script.lua ARGUMENTS...
wp --exec 'LUA CODE' ARGUMENTS...
wp --config alternate-startup.lua document.wp
```

`--lua` compiles and runs a file, passes remaining arguments through `...`, and
exits. `--exec` does the same for a source string. Both execute after core
modules and the initial document set exist but without starting the editor UI.
Place options that WordProcess itself must parse before `--lua` or `--exec`.

The startup file defaults to `~/.wordprocess/startup.lua`. It is loaded after
global settings and before screen initialisation. Use it for key overrides and
event listeners; avoid interactive screen calls before `ScreenInitialised`.

## Commands and state

High-level actions are functions in the global `Cmd` table. Useful examples
include `Cmd.LoadDocumentSet`, `Cmd.SaveCurrentDocumentAs`, import/export
functions, navigation and selection functions, insertion/deletion functions,
and style functions. The active state is exposed through `documentSet` and
`currentDocument`. Constructors include `CreateDocumentSet`, `CreateDocument`,
and `CreateParagraph`.

Use high-level commands when possible: they maintain indexes, dirty state,
menus, wrapping, events, and UI feedback. Direct table edits must explicitly
renumber or touch the owning object and are unsuitable for startup scripts that
expect forward compatibility.

## Events

Register with `AddEventListener(name, callback)` and retain the returned token
for `RemoveEventListener(token)`. `FireEvent` is synchronous; listener order is
undefined. `FireAsyncEvent` coalesces duplicate event names until the event-loop
flush and carries no arguments.

Common extension points include `RegisterAddons`, `ScreenInitialised`,
`DocumentLoaded`, `DocumentModified`, `Changed`, `WaitingForUser`, `Idle`,
`KeyTyped`, and `BuildStatusBar`. A `KeyTyped` listener receives a mutable
payload whose `value` can be transformed, as the smart-quotes add-on does.

## Key overrides

`OverrideKey(KEY, BINDING)` records an override used while building menu
accelerators. Bindings normally refer to an existing menu action. Key names use
the editor vocabulary, such as `^S`, `LEFT`, `SLEFT`, `^LEFT`, `PGDN`, and
`KEY_*` events supplied by the frontend. Invalid bindings raise an error early.

The compact-keyboard layer uses pseudo-key names such as `COMMAND_H`,
`COMMAND_RIGHTBRACKET`, and `COMMAND_SHIFT_D`. They use the same override API;
the full list and examples are in
[Keyboard shortcuts](keyboard-shortcuts.md#machine-wide-overrides-with-lua).
The in-program help resolves its labels from the active map, so overrides are
reflected there.

## Low-level API

The `wg` Lua table is the internal native bridge for screen, Unicode word,
filesystem, ZIP, clipboard, compression, clock, and process functions and
style constants. It remains named for source compatibility with the inherited
engine; it is not a filename extension. This API is lower-level and less stable
than `Cmd`, document objects, and the event interface.

## Bundled scripts

- `exportall.lua` exports every document in a set.
- `concat.lua` combines all documents into one named `all`.
- `dumpdoc.lua` diagnoses native serialization.
- `benchmark.lua` generates a large document and times save/load/export.

Run these from the source tree or install/adapt them as personal scripts. The
benchmark writes temporary files below `/tmp` and is intended for development.
