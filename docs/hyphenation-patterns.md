# Hyphenation patterns

WordProcess's Hyphenate wrap mode follows each language's own orthographic
rules for where a word may be broken (Knuth and Liang's pattern algorithm —
the same one TeX, LibreOffice and Firefox use), not a fixed set of
character-counting rules. The language logic itself comes entirely from
external pattern files; WordProcess only implements the generic algorithm
that applies them.

## Pattern file format

Pattern files use the standard `hyph_LL.dic` format (the same one the
`hyphen-*` system packages and LibreOffice/Firefox dictionary extensions
ship): a plain text file whose first line names an encoding (`UTF-8` or
`ISO8859-1`), followed by one pattern per line, e.g.:

```
UTF-8
hy3ph
hen5
in3flu4ence
```

An optional `LEFTHYPHENMIN`/`RIGHTHYPHENMIN` line declares the language's
own minimum number of characters required before/after a break (English
patterns declare 2 and 3, for instance); when present, WordProcess honours
it instead of falling back to a generic minimum.

## Getting pattern files

Most Linux distributions package these under names like `hyphen-en`,
`hyphen-de`, `hyphen-es`, `hyphen-fr`, installing to `/usr/share/hyphen/`.
LibreOffice's own dictionary extensions (including languages not covered by
a standalone package, such as Portuguese) also ship a `hyph_*.dic` file;
extracting one from an installed extension or `.oxt` package works equally
well.

## Selecting pattern files

WordProcess discovers `hyph_*.dic`/`hyph-*.dic` files automatically in:

- The directory configured at build time (`-Dhyphenation_dir=...`,
  conventionally `/usr/share/hyphen`).
- `~/.wordprocess/` — drop a file there for a personal selection that needs
  no root access.

Everything discovered is used by default. To choose a specific subset (for
example when several languages' pattern files are installed but only one
should apply), use **Document settings → Hyphenation…**; an explicit
selection there is preserved across restarts, the same way a spelling
dictionary selection is.

## When no pattern data applies

A word that no selected pattern file recognises (or is hyphenated with no
pattern files selected at all) still wraps correctly: WordProcess falls
back to the widest character cut that leaves at least two characters on
each side of the hyphen, exactly as it did before this feature existed.
