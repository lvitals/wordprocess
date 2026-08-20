# WordProcess documentation

This directory contains the complete user and developer documentation for
WordProcess. The source of truth is the running code; the documents describe
version 1.0 and native file format 8.

## Contents

- [Getting started](getting-started.md): installation, first launch, and the
  basic editing model.
- [Editor reference](editor.md): menus, keyboard commands, selection,
  navigation, styling, status information, and mouse behaviour.
- [Keyboard shortcuts](keyboard-shortcuts.md): every default binding,
  compact-keyboard navigation, menu rebinding, and Lua overrides.
- [Documents and publishing](documents-and-publishing.md): document sets,
  paragraph styles, page layouts, templates, autosave, and scrapbook.
- [Import and export](import-export.md): supported formats, conversion rules,
  fidelity, and batch examples.
- [Configuration](configuration.md): global and per-document settings, files,
  directories, dictionaries, and frontends.
- [Scripting](scripting.md): command-line Lua, startup customisation, events,
  commands, and bundled utility scripts.
- [Development](development.md): architecture, build options, tests, packaging,
  and project layout.

Traditional Unix manual pages are maintained separately in `man/`. Read them
with, for example, `man ./man/wp.1` or `mandoc man/wp.1`.
