# Mirrors tests/build.py: each test runs the (ncurses) binary as
# `<binary> --lua <name>.lua`, from the project root (so relative paths
# like "testdocs/..." used inside the .lua tests resolve), same as the `ab`
# test rule and same TEST_BINARY choice (config.py always points
# TEST_BINARY at the ncurses build on non-Windows).
wordprocess_tests = [
  'apply-markup', 'argument-parser', 'change-paragraph-style', 'clipboard',
  'compact-keyboard-navigation',
  'delete-selection', 'empty-wordcount', 'escape-strings', 'export-to-html', 'export-to-latex',
  'export-to-markdown', 'export-to-opendocument', 'export-to-org',
  'export-to-text', 'export-to-troff', 'filesystem', 'find-and-replace',
  'fixed-mode-click-preserves-viewport',
  'get-style-from-word', 'heading-styles', 'hyphenation', 'immutable-paragraphs',
  'import-from-html', 'import-from-markdown', 'import-from-opendocument',
  'import-from-text', 'import-from-wordstar', 'insert-space-with-style-hint',
  'line-boundary-navigation', 'line-down-into-style', 'line-up',
  'line-wrapping', 'long-word-wrapping', 'load-compatibility-01', 'load-compatibility-02', 'load-compatibility-03', 'load-compatibility-04',
  'load-compatibility-05', 'load-compatibility-06', 'load-compatibility-07', 'load-compatibility-08', 'load-compatibility-10-crlf',
  'load-compatibility-09', 'load-failed', 'load-wordgrinder', 'lowlevelclipboard',
  'margin-centered-with-width-cap', 'margin-mode-persistence',
  'move-while-selected',
  'numbered-lists', 'page-layout', 'page-navigation', 'parse-string-into-words', 'save-format-escaped-strings',
  'scrollbar', 'selection-shortcuts', 'simple-editing', 'smartquotes-selection', 'smartquotes-typing',
  'spellchecker', 'tab-insertion', 'tableio', 'textbuffer',
  'textbuffer-viewport-follows-backspace',
  'type-while-selected', 'undo', 'utf8', 'utils',
  'weirdness-cannot-save-settings', 'weirdness-combining-words',
  'weirdness-delete-word', 'weirdness-deletion-with-multiple-spaces',
  'weirdness-document-rename', 'weirdness-documentset-default-name',
  'weirdness-end-of-lines', 'weirdness-forward-delete',
  'weirdness-globals-applied-on-startup', 'weirdness-missing-clipboard',
  'weirdness-replacing-words', 'weirdness-save-new-document',
  'weirdness-splitting-lines-before-space',
  'weirdness-stray-control-char-in-export',
  'weirdness-style-bleeding-on-deletion', 'weirdness-styled-clipboard',
  'weirdness-styling-unicode', 'upgrade-compatibility-clipboard',
  'weirdness-word-left-from-end-of-line',
  'weirdness-word-left-on-first-word-in-doc',
  'weirdness-word-right-to-last-word-in-doc', 'windows-installdir', 'word',
  'xpattern',
]

foreach t : wordprocess_tests
  test(t, wordprocess_ncurses,
    args: ['--lua', meson.current_source_dir() / (t + '.lua')],
    workdir: meson.project_source_root(),
  )
endforeach

# Same tests again, run through valgrind's memcheck. Excluded from the
# default `meson test` run (own suite, and much slower) - opt in with
# `meson test --suite valgrind`.
valgrind_prog = find_program('valgrind', required: false)
if valgrind_prog.found()
  foreach t : wordprocess_tests
    test(t, valgrind_prog,
      args: [
        '--leak-check=full', '--show-leak-kinds=all', '--track-origins=yes',
        '--error-exitcode=99', '--quiet',
        wordprocess_ncurses.full_path(),
        '--lua', meson.current_source_dir() / (t + '.lua'),
      ],
      workdir: meson.project_source_root(),
      suite: 'valgrind',
      timeout: 60,
    )
  endforeach
endif
