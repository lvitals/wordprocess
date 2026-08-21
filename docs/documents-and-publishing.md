# Documents and publishing

## Document sets

A `.wp` file is a compressed native object graph identified as WordProcess
file format 8. It stores an ordered list of uniquely named documents, the
current document, set-level add-on settings, and per-document state. Editor
state such as menu accelerators, status-bar visibility, search text, spelling
preferences, and the machine-local filename is kept outside the document.
Saves are staged through a sibling `.new`
file before replacement to reduce the chance of leaving a partially written
file.

Older native formats 1 through 7 are upgraded by compatibility code and are
covered by regression fixtures. Loading a newer or invalid format fails rather
than silently discarding fields. Native files are not plain text and should not
be edited manually.

## Paragraph styles

| Code | Meaning | Export intent |
| --- | --- | --- |
| `P` | Plain body text | Normal paragraph |
| `H1`–`H4` | Heading levels 1–4 | Section hierarchy |
| `Q` | Indented text | Long quotation |
| `N` | Footnote or endnote | Small/special text |
| `C` | Figure or table caption | Caption text |
| `LB` | Bulleted list item | Unordered list |
| `LN` | Numbered list item | Ordered list |
| `L` | Unmarked list item | List continuation |
| `V` | Run-together indented text | Compact indented block |
| `PRE` | Preformatted text | Literal/preformatted block |
| `RAW` | Raw output data | Passed through by supporting exporters |

Heading paragraphs continue as `P` after Return. Numbered list counters reset
when a non-list paragraph is encountered. Body paragraph indentation and
vertical spacing follow global look-and-feel preferences.

## Page layout

Layout belongs to each document. All values must be positive. `Custom` starts
as A4, 21 × 29.7 cm, with 2.5 cm margins, 12 pt body text, 1.15 line spacing,
10 pt special text, 1.0 special spacing, and a 4 cm long-quote indent.

The `ABNT` profile uses A4; 3 cm top/left and 2 cm bottom/right margins; 12 pt,
1.5-spaced body text; 10 pt, single-spaced special text; and a 4 cm quotation
indent. The `Book` profile uses 14 × 21 cm; 1.8/1.6/2.0/2.0 cm top/right/bottom/
left margins; 11 pt body text with 1.2 spacing; 9 pt special text; and a 1 cm
quotation indent. Editing a preset value changes the profile label to Custom.

Exporters use exact physical values where supported. Page Preview converts the
printable width to terminal columns using an average glyph width of 0.5 em;
this is a writing preview, not a typesetting guarantee.

## Templates

Templates are ordinary `.wp` sets stored by default in
`~/.wordprocess/templates`. Saving as a template clears the stored output path,
so a document created from it starts unnamed. `default.wp` is loaded for every
new set when its file-format version matches the program. The template and
autosave directories can be changed globally.

## Autosave

Autosave is configured per document set and is disabled by default. The set
must first have been saved manually. The default interval is 10 minutes and the
default pattern is `%F.autosave.%T.wp`. `%F` expands to the base filename and
`%T` to a timestamp. Autosaves go beside the document unless a global autosave
directory is configured. Autosave files supplement manual saves; they do not
change the set's primary filename.

## Scrapbook

The scrapbook stores collected fragments in a document within the same set.
The default document name is `Scrapbook`. Copy-to-scrapbook preserves the
source; cut-to-scrapbook removes it. Timestamp headings are enabled by default
with `Item from '%N' at %T:`, where `%N` is the source document name and `%T`
is the current time. Paste-from-scrapbook uses the normal internal clipboard.

## Writing aids

Smart quotes can independently transform single and double quotation marks.
The default curly pairs are “/” and ‘/’. Transformation can be disabled inside
`RAW` paragraphs. Existing selections can be converted in either direction.

Spellchecking can highlight unknown words and combine a system dictionary with
the editor's user dictionary. Both dictionaries and spelling preferences are
global editor configuration and do not travel inside a `.wp` file. Older
hidden `User dictionary` documents are migrated and removed when opened.
Bundled American/Canadian and British dictionaries are installed as resources.
The `Pg:` status field uses the physical page layout configured for
the document; it is independent from the paragraph/style position field.
