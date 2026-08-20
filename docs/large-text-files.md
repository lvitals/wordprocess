# Large text files

Plain-text files at least 64 MiB are opened through WordProcess's native mapped
piece-table backend. The source is mapped read-only and edits are stored as
small independent pieces, so opening time and memory do not grow with the file
size. No external editor, process, or conversion tool is used.

Use **File > Import new document > Import text file**. The same editor commands
handle ordinary and mapped documents. Character movement is UTF-8 aware;
arrows, words, lines, pages, document boundaries, selection, clipboard,
find/replace, undo/redo, mouse positioning, and percentage/byte jumps operate
on byte ranges without first counting every line. The scrollbar position is an
approximation based on bytes.

The viewport translates byte offsets to UTF-8 boundaries and terminal-cell
widths before drawing or handling mouse positions. This includes combining
characters and double-width CJK/emoji cells. Exact line numbers are maintained
during sequential navigation; after a random byte/percentage jump or search,
the margin and status use `~` until an exact local line context is known.

`Ctrl-S` streams the logical document to `FILE.new`, flushes it, and atomically
replaces the source. **Save as** and plain-text export use the same bounded
pipeline. If the source path changed after opening, WordProcess asks before an
overwrite. Traditional autosave is skipped for mapped documents because each
snapshot would otherwise consume another complete multi-gigabyte file. Use
manual Save until a bounded delta journal is available.

When nothing changed, saving the original path is constant-time and does not
create or traverse `FILE.new`. After an edit, an atomic save must still write
the complete logical file. Linux transfers unchanged mapped pieces directly
between file descriptors inside the kernel; BSD and other Unix systems use the
portable sequential `write(2)` fallback.

Successful Save and Save As operations reopen and remap the saved destination,
so the monitored path, descriptor/handle, file identity and mapping always
refer to the same backing file. POSIX saves use an exclusive hidden temporary
in the destination directory, preserve mode/owner when permitted, fsync the
file and parent directory, and rename it. Windows uses replace/write-through
APIs and opens mappings with delete sharing so replacement is possible.

Mapped documents remain plain text. Paragraph/character styles and structured
exporters are refused with an explanation; they never silently materialise a
multi-gigabyte document. Clipboard selections are limited to 16 MiB because
system clipboards require an in-memory payload. Plain-text save/export has no
such limit.

Undo payload is bounded independently of the 500-revision count. Deletions up
to 64 MiB retain undo data with a single copy. Larger deletions remain allowed
but clear the undo/redo history and display a warning instead of allocating
multiple gigabytes. A future backing-store-referenced history can restore undo
for such unusually large single operations without sacrificing bounded RAM.

The automatic threshold can be changed in `~/.wordprocess/startup.lua`:

```lua
-- Use the piece-table backend for plain text at least 128 MiB.
GlobalSettings.large_file_threshold = 128 * 1024 * 1024
```

The minimum accepted value is 1 MiB. This setting affects plain-text import
only; native `.wp`, Markdown, HTML, and OpenDocument keep their structured
importers.

## Benchmark

Run the internal benchmark without modifying the source:

```sh
wp --lua scripts/benchmark-large-text.lua FILE
```

Pass a second path to include an atomic streaming-save measurement. Do not use
the source itself as the benchmark output.

```sh
wp --lua scripts/benchmark-large-text.lua FILE /tmp/large-output.txt
```

An optional third argument runs the random-edit benchmark and reports piece
count plus median and p99 insertion/deletion latency:

```sh
wp --lua scripts/benchmark-large-text.lua FILE '' 100000
```

“Mapped-file initialization” measures `open`/`fstat`/`mmap`, not throughput for
reading the complete file. RSS measures resident process pages; it does not
include every filesystem page that the operating-system page cache may retain
while navigating through the mapping.
