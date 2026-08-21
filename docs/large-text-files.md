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

Newly imported mapped documents begin as plain text. Saving them as native
`.wp` enables sparse paragraph/character metadata; structured exporters that
support mapped documents stream their output rather than silently materialising
a multi-gigabyte document. Clipboard selections are limited to
16 MiB because system clipboards require an in-memory payload. Plain-text
save/export has no such limit.

Saving a scalable document with a `.wp` suffix creates the versioned native
document container rather than plain text disguised by an extension. Its
header contains ordinary document-set metadata, content bounds, sparse
paragraph checkpoints, and reserved paragraph/character-style indexes. The
UTF-8 body follows the metadata and is mapped directly when the file is opened;
it is never copied into one Lua string. Subsequent saves stream the logical
piece-table content into an atomic replacement and remap only the body region.

Character styles (bold, italic, underline and normal) and paragraph styles are
stored as sparse byte-range spans. They are applied to selected text, rendered
only across the visible window, adjusted after text edits, and persisted in the
native metadata. Remaining document-wide tools are tracked in
[`ROADMAP.md`](../ROADMAP.md).

### Native document format

New ordinary and scalable `.wp` files both begin with
`WordProcess document v1`. For scalable storage it is followed
by fixed-width decimal metadata/content lengths and a CRC-32 of the metadata.
The metadata is the normal headerless WordProcess document-set representation;
the mapped UTF-8 body begins immediately afterwards. Loading validates all
ranges and the checksum before constructing indexes or mapping the body region.
A corrupt header, truncated body, oversized metadata block, or checksum
mismatch is rejected.

Saving creates an exclusive temporary file beside the destination, streams the
header and logical piece sequence, flushes the file, atomically renames it, and
flushes the parent directory on POSIX. The original remains in place when a
write fails before replacement. After success, the editor reopens the saved
path and remaps the exact content region, so external-file checks use the new
file identity rather than the imported source.

The automated suite opens and edits a sparse file larger than 4 GiB. This
exercises 64-bit offsets without allocating or writing 4 GiB of physical
storage.

Native saves also scan the piece sequence with constant auxiliary memory to
refresh exact word and logical-line counts plus sparse newline checkpoints.
Those cached values drive the status bar. Physical pagination is maintained in
a separate layout index; it is never derived from words or paragraphs. Editing
invalidates them immediately, so the
interface shows an unknown count rather than stale data until the next native
checkpoint rebuilds the index.

The serialized metadata calls this neutral structure `documentIndex`. The
historical `largeDocument` field is accepted only while loading old files,
migrated in memory, and omitted on the next save. An index describes the
current document layout; it does not classify a document as permanently large
or small, and remains valid as editing changes its size.

Mapped clipboard operations keep the 16 MiB safety limit, but now attach a
compact native payload containing character- and paragraph-style spans relative
to the copied range. Pasting into another mapped document restores those spans;
applications that understand only the system clipboard continue to receive the
same plain UTF-8 text.

Smart quotes operate directly on selected mapped ranges up to 16 MiB and
adjust sparse style offsets for UTF-8 replacements. Offline spellchecking
walks mapped documents circularly in 1 MiB windows, so its working set is
independent of document size.

Markdown, HTML, LaTeX, Org and troff exports write through a native streaming
file writer. ODT streams `content.xml` to temporary storage and then feeds that
file into the ZIP writer in 64 KiB blocks. None of these exporters builds the
complete result in a Lua string or table.

The save tests can inject a one-shot I/O error at temporary-file creation,
content writing, fsync, or rename. They verify that every pre-commit failure
leaves an existing destination unchanged and that a following save succeeds.

Mapped-document autosave writes a recoverable `WordProcess large journal v1`
file. The journal contains ordinary structured metadata, references to
unchanged ranges in the mapped base, and only the inserted byte blocks plus
piece descriptors. Its size is therefore proportional to edits and sparse
metadata, not to a multi-gigabyte document. Opening the autosave file remaps
the recorded base and applies the journal before exposing the recovered,
unsaved document.

The loader continues to accept the historical `WordProcess dumpfile` and
`WordProcess large document v1` signatures. Saving migrates either form to the
unified name. Older applications fail closed on the new versioned signature;
an unsupported future version reports that a newer application is required.

`Ctrl+G` opens the same combined Go To tool for every WordProcess document.
Its primary list is the structural table of contents: non-empty paragraphs
styled H1 through H4, hierarchical numbering, no body text or blank headings.
Page, absolute line, and 0–100 percent fields provide positional navigation.
Tab and Shift-Tab move focus; numeric fields do not treat H/J/K/L as browser
movement. Scalable storage reads only sparse paragraph-style spans and bounded
title previews (approximately 4 KiB), without scanning or materialising the
complete body. Line lookup starts at the nearest sparse newline checkpoint and
performs a bounded forward scan. Percentage lookup uses 64-bit byte positions
and backs up to a UTF-8 boundary.

Go To and the `Pg:` status field call the same physical-page navigation API.
Page dimensions, margins, font sizes, line spacing, indentation, styles and
wrapping determine its boundaries. Frequent status redraws use only the cached
layout index; they never rebuild it or scan the whole mapped file. If a mapped
document has no valid persisted index, `Pg: ?/?` is shown rather than a false
word-, line-, percentage-, or paragraph-based result. Clipboard-backed
scrapbook actions and the character-style status indicator also work with
scalable storage.

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

On 2026-08-21 the benchmark processed a 4,294,971,392-byte sparse file, made
1,000 deterministic random edits, and performed a complete streaming Save As.
Initialization took 16 µs, median edit latency was 56 µs (P99 133 µs), the
4 GiB save took 3.041 s, and reported RSS was 7,480 KiB. Results vary with the
storage device and operating-system cache.
