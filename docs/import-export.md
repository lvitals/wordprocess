# Import and export

## Format matrix

| Extension | Import | Export | Notes |
| --- | :---: | :---: | --- |
| `.wp` | Yes | Yes | Native document set; save/export includes the whole set |
| `.txt` | Yes | Yes | Plain UTF-8 text |
| `.md` | Yes | Yes | Markdown through libcmark and native callbacks |
| `.html` | Yes | Yes | Structural HTML with character styles |
| `.odt` | Yes | Yes | OpenDocument Text using ZIP/XML support |
| `.org` | No | Yes | Emacs Org mode |
| `.tex` | No | Yes | LaTeX |
| `.tr` | No | Yes | troff source |

Interactive import adds one document named from the source leaf name, adding a
numeric suffix when needed. Interactive export writes only the current
document, except a native `.wp` save, which writes the complete set.

## Command-line conversion

```sh
wp --convert INPUT OUTPUT
wp -c INPUT OUTPUT
```

Types are selected strictly from the final extension and are case-sensitive.
The input extensions are `wp`, `txt`, `md`, `html`, and `odt`; output also
supports `org`, `tex`, and `tr`. Both paths must have an extension.

A colon suffix selects or supplies a document name:

```sh
wp --convert novel.wp:"Chapter 2" chapter-2.odt
wp --convert essay.md:"Imported essay" collection.wp
```

For native input, the suffix selects an existing document. For another input
format, it renames the imported document. A suffix is forbidden on the output
path. Quote paths or names containing spaces. Conversion is non-interactive,
prints errors prefixed with `wp:`, and exits nonzero on failure.

## Fidelity

Native saves preserve every WordProcess object. Other formats represent only
the current document and may not support every concept. Heading and list styles
map naturally to semantic formats. Bold, italic, and underline are retained
when the target supports them. Plain text discards formatting. `RAW` paragraphs
bypass normal escaping in exporters that implement raw output, so they should
contain trusted target-language content.

ODT export uses page dimensions, margins, type sizes, spacing, and quote indent.
Text-oriented targets cannot reproduce physical pagination. Importers normalise
external structures into WordProcess's fixed paragraph-style vocabulary.

## Batch utilities

Export every document in a set, adding its index and name to the output path:

```sh
wp --lua scripts/exportall.lua novel.wp output.html
```

Concatenate all documents into a new document named `all`:

```sh
wp --lua scripts/concat.lua novel.wp combined.wp
```

`scripts/dumpdoc.lua` prints a diagnostic representation of the compressed
native file. It is a debugging tool, not a supported interchange format.

