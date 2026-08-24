# Converting a Hunspell dictionary to a word list

WordProcess's built-in spellchecker reads a plain UTF-8 file containing one
complete word per line. Hunspell dictionaries instead store stems in a `.dic`
file and morphological rules in a matching `.aff` file, so a `.dic` file must
not be selected directly.

## Expand the dictionary

Install a tool which provides the Hunspell `unmunch` command, then run:

```sh
unmunch /path/to/dictionary.dic /path/to/dictionary.aff > word-list.txt
```

`unmunch` expands the stems using the affix rules and writes complete forms.
The output uses the source dictionary's declared character encoding. Find the
`SET` directive near the beginning of the `.aff` file:

```sh
grep '^SET ' /path/to/dictionary.aff
```

When that encoding is not UTF-8, convert the stream while generating the list:

```sh
unmunch /path/to/dictionary.dic /path/to/dictionary.aff \
  | iconv -f SOURCE_ENCODING -t UTF-8 \
  > word-list.txt
```

Replace `SOURCE_ENCODING` with the value declared by `SET`. The command names
are examples; equivalent expansion and character-conversion tools may be used
on any platform.

Sort the file byte by byte and remove duplicate entries:

```sh
LC_ALL=C sort -u word-list.txt -o word-list.txt
```

## Validate the result

Verify known and deliberately invalid words with an exact-line search:

```sh
grep -x 'known-word' word-list.txt
grep -x 'deliberately-invalid-word' word-list.txt
```

The first command should print the known word and the second should print
nothing. Also verify that the file is detected as UTF-8 by an appropriate text
or encoding inspection tool.

Sorting is required: it lets WordProcess perform binary searches without
loading or indexing the entire dictionary. The file is opened through the
large-file text-buffer backend and only short candidate lines are read. A
bounded cache retains results for recently queried words, so memory use does
not grow with either dictionary size or document size. Offsets remain valid for
dictionaries larger than 4 GiB on platforms with 64-bit file offsets.

## Select the word list

Choose the generated file from **Global settings → Load new system
dictionary**. This explicit selection is stored as an editor preference.

To configure where installed lists are discovered, configure Meson before compiling:

```sh
meson configure builddir -Ddictionary_dir=/path/to/dictionaries
meson compile -C builddir
```

Use `-Ddictionary_path=/path/to/word-list.txt` only when one list should be
selected initially. Explicit selections in the editor are preserved.
